#import "Lite.h"
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>
#import <Accelerate/Accelerate.h>
#import <pthread.h>
#import "dr_flac.h"

NSNotificationName const FLPlayerDidChange = @"FLPlayerDidChange";

#pragma mark - Decoders

@interface FLFlacDecoder : NSObject <FLDecoding>
@end

@implementation FLFlacDecoder {
    drflac *_flac;
}

- (instancetype)initWithURL:(NSURL *)url {
    if ((self = [super init])) {
        _flac = drflac_open_file(url.fileSystemRepresentation, NULL);
        if (!_flac) return nil;
    }
    return self;
}

- (void)dealloc { if (_flac) drflac_close(_flac); }
- (double)sampleRate { return _flac->sampleRate; }
- (UInt32)channels { return _flac->channels; }
- (SInt64)frames { return (SInt64)_flac->totalPCMFrameCount; }
- (UInt32)read:(float *)out frames:(UInt32)count { return (UInt32)drflac_read_pcm_frames_f32(_flac, count, out); }
- (BOOL)seek:(SInt64)frame { return drflac_seek_to_pcm_frame(_flac, (drflac_uint64)frame); }

@end

@interface FLSystemDecoder : NSObject <FLDecoding>
@end

@implementation FLSystemDecoder {
    ExtAudioFileRef _file;
    double _rate;
    UInt32 _channels;
    SInt64 _frames;
}

- (instancetype)initWithURL:(NSURL *)url {
    if (!(self = [super init])) return nil;
    if (ExtAudioFileOpenURL((__bridge CFURLRef)url, &_file) != noErr) return nil;
    AudioStreamBasicDescription file = {0};
    UInt32 size = sizeof(file);
    ExtAudioFileGetProperty(_file, kExtAudioFileProperty_FileDataFormat, &size, &file);
    _rate = file.mSampleRate;
    _channels = MIN(MAX(file.mChannelsPerFrame, 1), 2);
    AudioStreamBasicDescription client = {0};
    client.mSampleRate = _rate;
    client.mFormatID = kAudioFormatLinearPCM;
    client.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
    client.mChannelsPerFrame = _channels;
    client.mBitsPerChannel = 32;
    client.mBytesPerFrame = client.mBytesPerPacket = 4 * _channels;
    client.mFramesPerPacket = 1;
    if (ExtAudioFileSetProperty(_file, kExtAudioFileProperty_ClientDataFormat, sizeof(client), &client) != noErr) return nil;
    size = sizeof(_frames);
    ExtAudioFileGetProperty(_file, kExtAudioFileProperty_FileLengthFrames, &size, &_frames);
    return self;
}

- (void)dealloc { if (_file) ExtAudioFileDispose(_file); }
- (double)sampleRate { return _rate; }
- (UInt32)channels { return _channels; }
- (SInt64)frames { return _frames; }

- (UInt32)read:(float *)out frames:(UInt32)count {
    AudioBufferList list;
    list.mNumberBuffers = 1;
    list.mBuffers[0].mNumberChannels = _channels;
    list.mBuffers[0].mDataByteSize = count * 4 * _channels;
    list.mBuffers[0].mData = out;
    UInt32 frames = count;
    return ExtAudioFileRead(_file, &frames, &list) == noErr ? frames : 0;
}

- (BOOL)seek:(SInt64)frame { return ExtAudioFileSeek(_file, frame) == noErr; }

@end

id<FLDecoding> FLOpenDecoder(NSURL *url) {
    if ([url.pathExtension.lowercaseString isEqualToString:@"flac"]) return [[FLFlacDecoder alloc] initWithURL:url];
    return [[FLSystemDecoder alloc] initWithURL:url];
}

#pragma mark - Stream

/// Where a song starts in a queue's timeline.
@interface FLMark : NSObject
@property (nonatomic) SInt64 queueFrame, trackFrame;
@property (nonatomic, strong) FLTrack *track;
@end

@implementation FLMark
@end

enum { FLBuffers = 4, FLBufferFrames = 4096, FLFFTLog = 11, FLFFTSize = 1 << FLFFTLog, FLHop = 1024, FLKept = 96 };

@interface FLPlayer ()
@property (nonatomic, readwrite, nullable) FLTrack *current;
@property (nonatomic, readwrite) BOOL playing;
- (nullable FLTrack *)trackAfter:(FLTrack *)track;
- (void)streamDidEnd:(id)stream;
@end

/// One audio queue at one sample rate. Songs at that rate follow each other in it with no gap; the analyzer
/// stamps each spectrum with the queue time it plays at.
@interface FLStream : NSObject
@property (nonatomic, readonly, nullable) FLTrack *after;
@property (nonatomic, readonly) FLMark *heard;
@property (nonatomic, readonly) double position;
- (nullable instancetype)initWithPlayer:(FLPlayer *)player decoder:(id<FLDecoding>)decoder track:(FLTrack *)track from:(SInt64)frame;
- (void)start;
- (void)pause;
- (void)dispose;
- (BOOL)spectrum:(float *)bands;
- (void)fill:(AudioQueueBufferRef)buffer queue:(AudioQueueRef)queue;
@end

static void FLOutput(void *user, AudioQueueRef queue, AudioQueueBufferRef buffer) {
    [(__bridge FLStream *)user fill:buffer queue:queue];
}

@implementation FLStream {
    AudioQueueRef _queue;
    AudioQueueBufferRef _buffers[FLBuffers];
    __weak FLPlayer *_player;
    id<FLDecoding> _decoder;
    FLTrack *_decoding;
    double _rate;
    float *_scratch;
    SInt64 _enqueued, _lastNow;
    int _outstanding;
    BOOL _finished, _disposed, _reported;
    NSMutableArray<FLMark *> *_marks;
    pthread_mutex_t _lock;

    FFTSetup _fft;
    float _window[FLFFTSize], _pending[FLFFTSize], _windowed[FLFFTSize];
    float _real[FLFFTSize / 2], _imag[FLFFTSize / 2], _power[FLFFTSize / 2];
    int _pendingCount;
    SInt64 _pendingStart;
    int _lo[FLBands], _hi[FLBands];
    float _tilt[FLBands];
    SInt64 _stamps[FLKept];
    float _spectra[FLKept][FLBands];
    int _head, _stored;
}

- (instancetype)initWithPlayer:(FLPlayer *)player decoder:(id<FLDecoding>)decoder track:(FLTrack *)track from:(SInt64)frame {
    if (!(self = [super init])) return nil;
    _player = player;
    _decoder = decoder;
    _decoding = track;
    _rate = decoder.sampleRate;
    if (frame > 0 && ![decoder seek:frame]) frame = 0;
    FLMark *mark = [FLMark new];
    mark.trackFrame = frame;
    mark.track = track;
    _marks = [NSMutableArray arrayWithObject:mark];
    pthread_mutex_init(&_lock, NULL);
    _scratch = malloc(FLBufferFrames * FLMaxChannels * sizeof(float));
    [self configureAnalyzer];

    AudioStreamBasicDescription format = {0};
    format.mSampleRate = _rate;
    format.mFormatID = kAudioFormatLinearPCM;
    format.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
    format.mChannelsPerFrame = 2;
    format.mBitsPerChannel = 32;
    format.mBytesPerFrame = format.mBytesPerPacket = 8;
    format.mFramesPerPacket = 1;
    // The queue holds the stream until -dispose, so a callback still running never meets a freed object.
    void *me = (__bridge_retained void *)self;
    if (AudioQueueNewOutput(&format, FLOutput, me, NULL, NULL, 0, &_queue) != noErr) {
        CFRelease(me);
        return nil;
    }
#if TARGET_OS_SIMULATOR
    // `-FLMute YES` tries it out without sound; the spectrum is taken before the volume.
    if ([NSUserDefaults.standardUserDefaults boolForKey:@"FLMute"]) AudioQueueSetParameter(_queue, kAudioQueueParam_Volume, 0);
#endif
    for (int i = 0; i < FLBuffers; i++) AudioQueueAllocateBuffer(_queue, FLBufferFrames * 8, &_buffers[i]);
    for (int i = 0; i < FLBuffers; i++) [self enqueue:_buffers[i] queue:_queue];
    return self;
}

- (void)dealloc {
    free(_scratch);
    if (_fft) vDSP_destroy_fftsetup(_fft);
    pthread_mutex_destroy(&_lock);
}

- (void)start {
    if (_disposed) return;
    AudioQueueStart(_queue, NULL);
    [self reportIfDry];
}

- (void)pause {
    if (!_disposed) AudioQueuePause(_queue);
}

- (void)dispose {
    if (_disposed) return;
    _disposed = YES;
    AudioQueueDispose(_queue, true);
    _queue = NULL;
    // Lets go of the queue's hold a moment later, in case a callback is still on its way out.
    void *me = (__bridge void *)self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{ CFRelease(me); });
}

- (void)fill:(AudioQueueBufferRef)buffer queue:(AudioQueueRef)queue {
    pthread_mutex_lock(&_lock);
    _outstanding--;
    pthread_mutex_unlock(&_lock);
    [self enqueue:buffer queue:queue];
    [self reportIfDry];
}

- (void)enqueue:(AudioQueueBufferRef)buffer queue:(AudioQueueRef)queue {
    if (_disposed || _finished) return;
    float *out = buffer->mAudioData;
    UInt32 got = 0;
    int hops = 0;
    while (got < FLBufferFrames) {
        UInt32 n = [_decoder read:_scratch frames:FLBufferFrames - got];
        if (n == 0) {
            if (++hops > 4 || ![self advanceAt:_enqueued + got]) {
                _finished = YES;
                break;
            }
            continue;
        }
        hops = 0;
        UInt32 channels = _decoder.channels;
        float *to = out + got * 2;
        if (channels == 2) {
            memcpy(to, _scratch, n * 8);
        } else {
            for (UInt32 i = 0; i < n; i++) {
                to[2 * i] = _scratch[i * channels];
                to[2 * i + 1] = _scratch[i * channels + (channels > 1 ? 1 : 0)];
            }
        }
        got += n;
    }
    if (got == 0) return;
    if (_player.analyzes) [self analyze:out frames:got at:_enqueued];
    else _pendingCount = 0;
    buffer->mAudioDataByteSize = got * 8;
    if (AudioQueueEnqueueBuffer(queue, buffer, 0, NULL) == noErr) {
        pthread_mutex_lock(&_lock);
        _outstanding++;
        pthread_mutex_unlock(&_lock);
        _enqueued += got;
    }
}

/// The song ran out: carry straight on into the next one if it plays at the same rate.
- (BOOL)advanceAt:(SInt64)queueFrame {
    FLTrack *next = [_player trackAfter:_decoding];
    if (!next) return NO;
    id<FLDecoding> decoder = FLOpenDecoder(next.url);
    if (!decoder || decoder.sampleRate != _rate) {
        _after = next;
        return NO;
    }
    _decoder = decoder;
    _decoding = next;
    FLMark *mark = [FLMark new];
    mark.queueFrame = queueFrame;
    mark.track = next;
    pthread_mutex_lock(&_lock);
    [_marks addObject:mark];
    if (_marks.count > 8) [_marks removeObjectAtIndex:0];
    pthread_mutex_unlock(&_lock);
    return YES;
}

- (void)reportIfDry {
    pthread_mutex_lock(&_lock);
    BOOL dry = _finished && _outstanding <= 0 && !_reported;
    if (dry) _reported = YES;
    pthread_mutex_unlock(&_lock);
    if (!dry) return;
    __weak FLStream *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        FLStream *stream = weakSelf;
        FLPlayer *player = stream ? stream->_player : nil;
        [player streamDidEnd:stream];
    });
}

- (SInt64)now {
    AudioTimeStamp time = {0};
    if (_queue && AudioQueueGetCurrentTime(_queue, NULL, &time, NULL) == noErr && (time.mFlags & kAudioTimeStampSampleTimeValid)) {
        _lastNow = MAX(0, (SInt64)time.mSampleTime);
    }
    return _lastNow;
}

- (FLMark *)markAt:(SInt64)now {
    pthread_mutex_lock(&_lock);
    FLMark *found = _marks.firstObject;
    for (FLMark *mark in _marks) if (mark.queueFrame <= now) found = mark;
    pthread_mutex_unlock(&_lock);
    return found;
}

- (FLMark *)heard { return [self markAt:self.now]; }

- (double)position {
    SInt64 now = self.now;
    FLMark *mark = [self markAt:now];
    return (mark.trackFrame + MAX(0, now - mark.queueFrame)) / _rate;
}

#pragma mark Analyzer

/// Bands spaced evenly in pitch from 40 Hz to 16 kHz, as in Flaco.
- (void)configureAnalyzer {
    _fft = vDSP_create_fftsetup(FLFFTLog, kFFTRadix2);
    vDSP_hann_window(_window, FLFFTSize, vDSP_HANN_DENORM);
    double bin = _rate / FLFFTSize, low = 40, high = MIN(16000, _rate / 2);
    for (int b = 0; b < FLBands; b++) {
        double f0 = low * pow(high / low, (double)b / FLBands), f1 = low * pow(high / low, (double)(b + 1) / FLBands);
        int lo = MAX(1, (int)(f0 / bin));
        _lo[b] = lo;
        _hi[b] = MIN(MAX(lo + 1, (int)(f1 / bin)), FLFFTSize / 2);
        // Music falls off toward the treble; lift it 3 dB an octave above 1 kHz so the top bands move too.
        _tilt[b] = 3 * log2(low * pow(high / low, (b + 0.5) / FLBands) / 1000);
    }
}

- (void)analyze:(const float *)stereo frames:(UInt32)count at:(SInt64)start {
    for (UInt32 i = 0; i < count; i++) {
        if (_pendingCount == 0) _pendingStart = start + i;
        _pending[_pendingCount++] = (stereo[2 * i] + stereo[2 * i + 1]) * 0.5f;
        if (_pendingCount == FLFFTSize) {
            [self spectrumAt:_pendingStart + FLFFTSize / 2];
            memmove(_pending, _pending + FLHop, (FLFFTSize - FLHop) * sizeof(float));
            _pendingCount = FLFFTSize - FLHop;
            _pendingStart += FLHop;
        }
    }
}

- (void)spectrumAt:(SInt64)stamp {
    vDSP_vmul(_pending, 1, _window, 1, _windowed, 1, FLFFTSize);
    DSPSplitComplex split = {_real, _imag};
    vDSP_ctoz((const DSPComplex *)_windowed, 2, &split, 1, FLFFTSize / 2);
    vDSP_fft_zrip(_fft, &split, 1, FLFFTLog, kFFTDirection_Forward);
    vDSP_zvmags(&split, 1, _power, 1, FLFFTSize / 2);
    // A full-scale sine peaks at (size / 2)² after the windowed real FFT.
    float fullScale = (float)(FLFFTSize / 2) * (FLFFTSize / 2);
    float bands[FLBands];
    for (int b = 0; b < FLBands; b++) {
        float sum = 0;
        for (int k = _lo[b]; k < _hi[b]; k++) sum += _power[k];
        float decibels = 10 * log10f(MAX(sum / (_hi[b] - _lo[b]) / fullScale, 1e-12f)) + _tilt[b];
        bands[b] = MIN(MAX((decibels + 66) / 60, 0), 1);
    }
    pthread_mutex_lock(&_lock);
    _stamps[_head] = stamp;
    memcpy(_spectra[_head], bands, sizeof(bands));
    _head = (_head + 1) % FLKept;
    _stored = MIN(_stored + 1, FLKept);
    pthread_mutex_unlock(&_lock);
}

- (BOOL)spectrum:(float *)bands {
    SInt64 now = self.now;
    BOOL found = NO;
    pthread_mutex_lock(&_lock);
    for (int k = 0; k < _stored; k++) {
        int i = (_head - 1 - k + FLKept) % FLKept;
        if (_stamps[i] <= now) {
            memcpy(bands, _spectra[i], sizeof(float) * FLBands);
            found = YES;
            break;
        }
    }
    pthread_mutex_unlock(&_lock);
    return found;
}

@end

#pragma mark - Player

@implementation FLPlayer {
    FLStream *_stream;
    NSArray<FLTrack *> *_list;
    NSArray<NSNumber *> *_order;
    NSInteger _pos;
    double _resumeAt;
    FLMark *_heard;
    BOOL _resumeAfterInterruption;
}

+ (FLPlayer *)shared {
    static FLPlayer *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [FLPlayer new]; });
    return shared;
}

- (instancetype)init {
    if ((self = [super init])) {
        _list = @[];
        _order = @[];
        self.analyzes = YES;
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        [center addObserver:self selector:@selector(interrupted:) name:AVAudioSessionInterruptionNotification object:nil];
        [center addObserver:self selector:@selector(routeChanged:) name:AVAudioSessionRouteChangeNotification object:nil];
        [NSTimer scheduledTimerWithTimeInterval:0.25 target:self selector:@selector(tick) userInfo:nil repeats:YES];
        [self setUpRemote];
    }
    return self;
}

- (double)position { return _stream ? _stream.position : _resumeAt; }

#pragma mark The list

/// Under the lock. Looks from the current place on, so a song in the list twice is found where it plays.
- (NSInteger)placeOf:(FLTrack *)track {
    NSInteger count = _order.count;
    for (NSInteger k = 0; k < count; k++) {
        NSInteger p = (_pos + k) % count;
        if ([_list[_order[p].integerValue] isEqual:track]) return p;
    }
    return NSNotFound;
}

/// Under the lock. With shuffle on, the song stays first and the rest follow in a new order.
- (void)reorderKeeping:(FLTrack *)track {
    NSInteger index = track ? [_list indexOfObject:track] : NSNotFound;
    if (index == NSNotFound) index = 0;
    NSMutableArray<NSNumber *> *order = [NSMutableArray array];
    for (NSUInteger i = 0; i < _list.count; i++) [order addObject:@(i)];
    if (_shuffle && order.count > 1) {
        [order removeObjectAtIndex:index];
        for (NSUInteger i = order.count - 1; i > 0; i--) [order exchangeObjectAtIndex:i withObjectAtIndex:arc4random_uniform((uint32_t)i + 1)];
        [order insertObject:@(index) atIndex:0];
        _pos = 0;
    } else {
        _pos = index;
    }
    _order = order;
}

/// What plays when `track` ends by itself. Called from the audio thread.
- (FLTrack *)trackAfter:(FLTrack *)track {
    @synchronized (self) {
        if (_repeatMode == FLRepeatOne) return track;
        NSInteger p = [self placeOf:track];
        if (p == NSNotFound) return nil;
        if (p + 1 < (NSInteger)_order.count) return _list[_order[p + 1].integerValue];
        return _repeatMode == FLRepeatAll ? _list[_order[0].integerValue] : nil;
    }
}

/// What the buttons step to: like the list running on, but repeat one doesn't hold them.
- (FLTrack *)step:(NSInteger)direction {
    @synchronized (self) {
        NSInteger count = _order.count, p = _current ? [self placeOf:_current] : NSNotFound;
        if (count == 0 || p == NSNotFound) return nil;
        NSInteger q = p + direction;
        if (q < 0 || q >= count) {
            if (_repeatMode == FLRepeatOff) return nil;
            q = (q + count) % count;
        }
        return _list[_order[q].integerValue];
    }
}

- (void)setShuffle:(BOOL)shuffle {
    @synchronized (self) {
        _shuffle = shuffle;
        [self reorderKeeping:_current];
    }
    [self changed];
}

- (void)setRepeatMode:(FLRepeat)repeatMode {
    @synchronized (self) { _repeatMode = repeatMode; }
    [self changed];
}

#pragma mark Playing

- (void)playTrack:(FLTrack *)track inList:(NSArray<FLTrack *> *)list {
    @synchronized (self) {
        _list = [list copy];
        [self reorderKeeping:track];
    }
    [self playFrom:track];
}

/// Starts `track`, or the first song after it that opens.
- (void)playFrom:(FLTrack *)track {
    NSUInteger tries = MAX(_list.count, 1);
    while (track && tries-- > 0) {
        if ([self startTrack:track at:0 playing:YES]) return;
        track = [self trackAfter:track];
    }
    [self stop];
}

- (BOOL)startTrack:(FLTrack *)track at:(double)seconds playing:(BOOL)play {
    [_stream dispose];
    _stream = nil;
    id<FLDecoding> decoder = FLOpenDecoder(track.url);
    if (!decoder || decoder.sampleRate <= 0) return NO;
    [self activateAt:decoder.sampleRate];
    FLStream *stream = [[FLStream alloc] initWithPlayer:self decoder:decoder track:track from:(SInt64)(seconds * decoder.sampleRate)];
    if (!stream) return NO;
    _stream = stream;
    _heard = stream.heard;
    _resumeAt = seconds;
    @synchronized (self) {
        NSInteger p = [self placeOf:track];
        if (p != NSNotFound) _pos = p;
    }
    self.current = track;
    self.playing = play;
    if (play) [stream start];
    [self changed];
    return YES;
}

- (void)streamDidEnd:(FLStream *)stream {
    if (stream != _stream) return;
    if (stream.after) [self playFrom:stream.after];
    else [self stop];
}

- (void)toggle {
    if (!_current) {
        NSArray *all = FLLibrary.shared.tracks;
        if (all.count) [self playTrack:all[0] inList:all];
        return;
    }
    if (!_stream) {
        if (![self startTrack:_current at:_resumeAt playing:YES]) [self playFrom:[self trackAfter:_current]];
        return;
    }
    if (_playing) {
        _resumeAt = self.position;
        [_stream pause];
        self.playing = NO;
    } else {
        [self activateAt:0];
        [_stream start];
        self.playing = YES;
    }
    [self changed];
}

- (void)stop {
    [_stream dispose];
    _stream = nil;
    _resumeAt = 0;
    self.playing = NO;
    [self changed];
}

- (void)next {
    FLTrack *next = [self step:1];
    if (next) [self playFrom:next];
    else [self stop];
}

- (void)previous {
    FLTrack *previous = [self step:-1];
    if (self.position > 3 || !previous) [self seekTo:0];
    else [self playFrom:previous];
}

- (void)seekTo:(double)seconds {
    if (!_current) return;
    seconds = MAX(0, MIN(seconds, _current.duration - 0.25));
    if (_stream) {
        [self startTrack:_current at:seconds playing:_playing];
    } else {
        _resumeAt = seconds;
        [self changed];
    }
}

- (BOOL)spectrum:(float *)bands { return _stream && self.analyzes ? [_stream spectrum:bands] : NO; }

/// Notices when the speaker reaches the next song in a gapless run.
- (void)tick {
    if (!_stream) return;
    FLMark *heard = _stream.heard;
    if (heard == _heard) return;
    _heard = heard;
    @synchronized (self) {
        NSInteger p = [self placeOf:heard.track];
        if (p != NSNotFound) _pos = p;
    }
    self.current = heard.track;
    [self changed];
}

- (void)changed {
    [self updateNowPlaying];
    [NSNotificationCenter.defaultCenter postNotificationName:FLPlayerDidChange object:self];
}

#pragma mark The system

/// Asks for the song's own rate, so a CD rip isn't resampled where the output allows.
- (void)activateAt:(double)rate {
    AVAudioSession *session = AVAudioSession.sharedInstance;
    [session setCategory:AVAudioSessionCategoryPlayback error:nil];
    if (rate > 0 && session.preferredSampleRate != rate) [session setPreferredSampleRate:rate error:nil];
    [session setActive:YES error:nil];
}

- (void)interrupted:(NSNotification *)note {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSUInteger type = [note.userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue];
        if (type == AVAudioSessionInterruptionTypeBegan) {
            self->_resumeAfterInterruption = self.playing;
            if (self.playing) [self toggle];
        } else {
            NSUInteger options = [note.userInfo[AVAudioSessionInterruptionOptionKey] unsignedIntegerValue];
            if (self->_resumeAfterInterruption && (options & AVAudioSessionInterruptionOptionShouldResume) && !self.playing) [self toggle];
            self->_resumeAfterInterruption = NO;
        }
    });
}

/// Headphones out: pause rather than play on through the speaker.
- (void)routeChanged:(NSNotification *)note {
    NSUInteger reason = [note.userInfo[AVAudioSessionRouteChangeReasonKey] unsignedIntegerValue];
    if (reason != AVAudioSessionRouteChangeReasonOldDeviceUnavailable) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.playing) [self toggle];
    });
}

- (void)setUpRemote {
    MPRemoteCommandCenter *center = MPRemoteCommandCenter.sharedCommandCenter;
    __weak FLPlayer *weakSelf = self;
    [center.playCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event) {
        if (!weakSelf.playing) [weakSelf toggle];
        return MPRemoteCommandHandlerStatusSuccess;
    }];
    [center.pauseCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event) {
        if (weakSelf.playing) [weakSelf toggle];
        return MPRemoteCommandHandlerStatusSuccess;
    }];
    [center.togglePlayPauseCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event) {
        [weakSelf toggle];
        return MPRemoteCommandHandlerStatusSuccess;
    }];
    [center.nextTrackCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event) {
        [weakSelf next];
        return MPRemoteCommandHandlerStatusSuccess;
    }];
    [center.previousTrackCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event) {
        [weakSelf previous];
        return MPRemoteCommandHandlerStatusSuccess;
    }];
    [center.changePlaybackPositionCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event) {
        [weakSelf seekTo:((MPChangePlaybackPositionCommandEvent *)event).positionTime];
        return MPRemoteCommandHandlerStatusSuccess;
    }];
}

- (void)updateNowPlaying {
    MPNowPlayingInfoCenter *center = MPNowPlayingInfoCenter.defaultCenter;
    FLTrack *track = _current;
    if (!track) {
        center.nowPlayingInfo = nil;
        return;
    }
    NSMutableDictionary *info = [@{
        MPMediaItemPropertyTitle: track.title, MPMediaItemPropertyArtist: track.artist,
        MPMediaItemPropertyAlbumTitle: track.album, MPMediaItemPropertyPlaybackDuration: @(track.duration),
        MPNowPlayingInfoPropertyElapsedPlaybackTime: @(self.position), MPNowPlayingInfoPropertyPlaybackRate: @(_playing ? 1 : 0),
    } mutableCopy];
    FLAlbum *album = [FLLibrary.shared albumForTrack:track];
    UIImage *cover = album ? [FLLibrary.shared coverForAlbum:album large:YES] : nil;
    if (cover) {
        info[MPMediaItemPropertyArtwork] = [[MPMediaItemArtwork alloc] initWithBoundsSize:cover.size requestHandler:^UIImage *(CGSize size) { return cover; }];
    }
    center.nowPlayingInfo = info;
}

#pragma mark Saving

- (void)save {
    NSMutableDictionary *state = [NSMutableDictionary dictionary];
    @synchronized (self) { state[@"list"] = [_list valueForKey:@"path"] ?: @[]; }
    if (_current) state[@"current"] = _current.path;
    state[@"position"] = @(self.position);
    state[@"shuffle"] = @(_shuffle);
    state[@"repeat"] = @(_repeatMode);
    [NSUserDefaults.standardUserDefaults setObject:state forKey:@"player"];
}

- (void)restore {
    NSDictionary *state = [NSUserDefaults.standardUserDefaults dictionaryForKey:@"player"];
    FLLibrary *library = FLLibrary.shared;
    FLTrack *current = [library trackAtPath:state[@"current"] ?: @""];
    _repeatMode = [state[@"repeat"] integerValue];
    _shuffle = [state[@"shuffle"] boolValue];
    if (!current) return;
    NSMutableArray *list = [NSMutableArray array];
    for (NSString *path in state[@"list"]) {
        FLTrack *track = [library trackAtPath:path];
        if (track) [list addObject:track];
    }
    @synchronized (self) {
        _list = list.count ? list : library.tracks;
        [self reorderKeeping:current];
    }
    _resumeAt = [state[@"position"] doubleValue];
    self.current = current;
    [self changed];
}

@end

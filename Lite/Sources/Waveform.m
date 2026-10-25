#import "Lite.h"

NSNotificationName const FLWaveformDidChange = @"FLWaveformDidChange";

/// Loudness on a fixed scale, −33 to −3 dBFS RMS, as in Flaco: quiet passages look quiet in every song.
static float FLLevel(double meanSquare) {
    double decibels = 10 * log10(MAX(meanSquare, 1e-12));
    return (float)MIN(MAX((decibels + 33) / 30, 0), 1);
}

@implementation FLWaveforms {
    dispatch_queue_t _queue;
    NSMutableDictionary<NSString *, NSData *> *_done, *_partial;
    NSString *_wanted;
}

+ (FLWaveforms *)shared {
    static FLWaveforms *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [FLWaveforms new]; });
    return shared;
}

- (instancetype)init {
    if ((self = [super init])) {
        _queue = dispatch_queue_create("lite.waveforms", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0));
        _done = [NSMutableDictionary dictionary];
        _partial = [NSMutableDictionary dictionary];
    }
    return self;
}

- (NSURL *)fileFor:(FLTrack *)track {
    NSURL *caches = [NSFileManager.defaultManager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL *folder = [caches URLByAppendingPathComponent:@"Lite/Waves"];
    [NSFileManager.defaultManager createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *key = [NSString stringWithFormat:@"%@\n%lld", track.path, track.size];
    uint64_t h = 0xcbf29ce484222325ULL;
    for (const char *c = key.UTF8String; *c; c++) { h ^= (uint8_t)*c; h *= 0x100000001b3ULL; }
    return [folder URLByAppendingPathComponent:[NSString stringWithFormat:@"%llx.bin", h]];
}

- (NSData *)levelsFor:(FLTrack *)track {
    if (!track) return nil;
    NSData *levels = _done[track.path];
    if (levels) return levels;
    levels = [NSData dataWithContentsOfURL:[self fileFor:track]];
    if (levels.length == FLWaveBars * sizeof(float)) {
        _done[track.path] = levels;
        return levels;
    }
    return _partial[track.path];
}

- (void)prepare:(FLTrack *)track {
    if (!track) return;
    [self levelsFor:track];
    if (_done[track.path]) return;
    @synchronized (self) { _wanted = track.path; }
    dispatch_async(_queue, ^{ [self decode:track]; });
}

- (BOOL)stillWanted:(FLTrack *)track {
    @synchronized (self) { return [_wanted isEqualToString:track.path]; }
}

- (void)publish:(const float *)levels for:(FLTrack *)track finished:(BOOL)finished {
    NSData *data = [NSData dataWithBytes:levels length:FLWaveBars * sizeof(float)];
    if (finished) [data writeToURL:[self fileFor:track] atomically:YES];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (finished) {
            self->_done[track.path] = data;
            [self->_partial removeObjectForKey:track.path];
        } else {
            self->_partial[track.path] = data;
        }
        [NSNotificationCenter.defaultCenter postNotificationName:FLWaveformDidChange object:track.path];
    });
}

/// The whole song is decoded, so it runs at utility priority, only for the song on screen, and waits while
/// Flaco Lite is out of sight.
- (void)decode:(FLTrack *)track {
    if (![self stillWanted:track] || [NSFileManager.defaultManager fileExistsAtPath:[self fileFor:track].path]) return;
    id<FLDecoding> decoder = FLOpenDecoder(track.url);
    if (!decoder || decoder.frames <= 0) return;
    float levels[FLWaveBars];
    for (int i = 0; i < FLWaveBars; i++) levels[i] = -1;
    SInt64 perBar = MAX(1, decoder.frames / FLWaveBars), inBar = 0;
    UInt32 channels = decoder.channels;
    float *buffer = malloc(4096 * FLMaxChannels * sizeof(float));
    double sum = 0;
    int bar = 0;
    CFAbsoluteTime published = CFAbsoluteTimeGetCurrent();
    while (bar < FLWaveBars) {
        while (self.paused) usleep(250000);
        if (![self stillWanted:track]) break;
        UInt32 n = [decoder read:buffer frames:4096];
        if (n == 0) break;
        for (UInt32 i = 0; i < n && bar < FLWaveBars; i++) {
            float sample = channels > 1 ? (buffer[i * channels] + buffer[i * channels + 1]) * 0.5f : buffer[i];
            sum += sample * sample;
            if (++inBar == perBar) {
                levels[bar++] = FLLevel(sum / inBar);
                sum = 0;
                inBar = 0;
            }
        }
        if (CFAbsoluteTimeGetCurrent() - published > 0.3) {
            published = CFAbsoluteTimeGetCurrent();
            [self publish:levels for:track finished:NO];
        }
    }
    free(buffer);
    if (![self stillWanted:track]) return;
    if (bar < FLWaveBars && inBar > 0) levels[bar++] = FLLevel(sum / inBar);
    for (; bar < FLWaveBars; bar++) levels[bar] = 0;
    [self publish:levels for:track finished:YES];
}

@end

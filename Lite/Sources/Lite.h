// Flaco Lite: Flaco for the iPhone 5c on iOS 10, in Objective-C, playing local files with its own FLAC decoder.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// A song in Documents, with what its tags say.
@interface FLTrack : NSObject
@property (nonatomic, copy) NSString *path;  // relative to Documents
@property (nonatomic, copy) NSString *title, *artist, *album, *albumArtist, *format;
@property (nonatomic) NSInteger number, disc, year, bits, channels;
@property (nonatomic) double duration, sampleRate, modified;
@property (nonatomic) long long size;
@property (nonatomic, readonly) NSURL *url;
@property (nonatomic, readonly) NSString *albumKey;
/// `FLAC | 936 kbps | 44.1 kHz | 16 bit`
@property (nonatomic, readonly) NSString *status;
- (instancetype)initWithDictionary:(NSDictionary *)dictionary;
- (NSDictionary *)dictionary;
@end

@interface FLAlbum : NSObject
@property (nonatomic, copy) NSString *key, *title, *artist, *coverID;
@property (nonatomic) NSInteger year;
@property (nonatomic, copy) NSArray<FLTrack *> *tracks;
@property (nonatomic, readonly) double duration;
@property (nonatomic, readonly) long long size;
@end

/// The interface's colours, all from the playing cover: a dark ground in its main hue, an accent from its most
/// vivid other colour.
@interface FLTheme : NSObject
@property (nonatomic, strong) UIColor *background, *glow, *panel, *line, *accent, *text;
@property (nonatomic, readonly) UIColor *secondary, *faint, *tint;
+ (FLTheme *)neutral;
+ (FLTheme *)paletteFromImage:(UIImage *)image;
- (instancetype)initWithArray:(NSArray<NSNumber *> *)hexes;
- (NSArray<NSNumber *> *)array;
- (FLTheme *)mix:(FLTheme *)other amount:(CGFloat)t;
@end

extern NSNotificationName const FLLibraryDidChange;

/// Every audio file under Documents, grouped into albums. The index is kept on disk so launch shows the
/// library at once; covers are kept as small and large JPEGs.
@interface FLLibrary : NSObject
@property (class, readonly) FLLibrary *shared;
@property (class, readonly) NSURL *documents;
@property (nonatomic, readonly) NSArray<FLAlbum *> *albums;
@property (nonatomic, readonly) NSArray<FLTrack *> *tracks;
@property (nonatomic, readonly) BOOL scanning;
- (void)load;
- (void)scan;
- (nullable FLTrack *)trackAtPath:(NSString *)path;
- (nullable FLAlbum *)albumForTrack:(FLTrack *)track;
- (nullable UIImage *)coverForAlbum:(FLAlbum *)album large:(BOOL)large;
- (FLTheme *)themeForTrack:(nullable FLTrack *)track;
@end

/// Reads a song as interleaved float frames, `channels` per frame.
@protocol FLDecoding <NSObject>
@property (nonatomic, readonly) double sampleRate;
@property (nonatomic, readonly) UInt32 channels;
@property (nonatomic, readonly) SInt64 frames;
/// Up to `count` frames; 0 at the end.
- (UInt32)read:(float *)out frames:(UInt32)count;
- (BOOL)seek:(SInt64)frame;
@end

#define FLMaxChannels 8

/// dr_flac for FLAC, which iOS 10 can't read; the system's decoders for everything else.
id<FLDecoding> _Nullable FLOpenDecoder(NSURL *url);

extern NSNotificationName const FLWaveformDidChange;
#define FLWaveBars 96

/// A song's loudness outline for the seekbar, decoded once in the background and kept.
@interface FLWaveforms : NSObject
@property (class, readonly) FLWaveforms *shared;
/// While Flaco Lite is out of sight.
@property (atomic) BOOL paused;
/// FLWaveBars floats from 0 to 1, -1 for bars not decoded yet; nil before the song has been looked at.
- (nullable NSData *)levelsFor:(FLTrack *)track;
- (void)prepare:(FLTrack *)track;
@end

typedef NS_ENUM(NSInteger, FLRepeat) { FLRepeatOff, FLRepeatAll, FLRepeatOne };

extern NSNotificationName const FLPlayerDidChange;
#define FLBands 32

/// Plays through an audio queue, gapless between songs of the same sample rate.
@interface FLPlayer : NSObject
@property (class, readonly) FLPlayer *shared;
@property (nonatomic, readonly, nullable) FLTrack *current;
@property (nonatomic, readonly) BOOL playing;
@property (nonatomic, readonly) double position;
@property (nonatomic) BOOL shuffle;
@property (nonatomic) FLRepeat repeatMode;
/// Off while Flaco Lite is out of sight: nobody sees the spectrum, and iOS limits a background app's CPU.
@property (atomic) BOOL analyzes;
- (void)playTrack:(FLTrack *)track inList:(NSArray<FLTrack *> *)list;
- (void)toggle;
- (void)stop;
- (void)next;
- (void)previous;
- (void)seekTo:(double)seconds;
/// The spectrum of what's coming out of the speaker now, FLBands levels from 0 to 1.
- (BOOL)spectrum:(float *)bands;
- (void)save;
- (void)restore;
@end

@interface FLMainViewController : UIViewController
@end

NSString *FLClock(double seconds);
UIFont *FLMono(CGFloat size);

NS_ASSUME_NONNULL_END

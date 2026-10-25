// Flaco: a FLAC player for the iPhone 5c on iOS 10 and the 6s on iOS 15, one app in Objective-C with its own FLAC decoder.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// A song in Documents, with what its tags say.
@interface FLTrack : NSObject
@property (nonatomic, copy) NSString *path;  // relative to Documents
@property (nonatomic, copy) NSString *title, *artist, *album, *albumArtist, *format;
@property (nonatomic) NSInteger number, disc, year, bits, channels;
@property (nonatomic) double duration, sampleRate, modified;
@property (nonatomic) long long size;
/// ReplayGain in dB and the peak as a fraction of full scale; NAN when the tags don't say.
@property (nonatomic) double trackGain, albumGain, trackPeak, albumPeak;
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
/// While Flaco is out of sight.
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
/// Off while Flaco is out of sight: nobody sees the spectrum, and iOS limits a background app's CPU.
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
NSString *FLSize(long long bytes);
CGFloat FLHairline(void);
UIEdgeInsets FLInsets(UIView *view);
UILabel *FLLabel(UIFont *font, NSTextAlignment alignment);
UIImage *FLIcon(NSString *name);
UIButton *FLIconButton(NSString *name, NSString *label);
/// The theme on screen now, for pages opened over the player.
FLTheme *FLCurrentTheme(void);

#pragma mark - Settings

extern NSNotificationName const FLSettingsDidChange;

@interface FLSettings : NSObject
/// Album gain where the tags have it, else track gain. On unless turned off.
@property (class, nonatomic) BOOL replayGain;
@end

#pragma mark - Server

/// A song on the server, and where it goes under Documents.
@interface FLSong : NSObject
@property (nonatomic, copy) NSString *songID, *path, *albumID, *title, *artist, *album, *albumArtist;
@property (nonatomic, copy, nullable) NSString *coverArt;
@property (nonatomic) long long size;
@property (nonatomic) NSInteger year;
- (instancetype)initWithDictionary:(NSDictionary *)dictionary;
- (NSDictionary *)dictionary;
@end

/// A Subsonic server: Navidrome, or any other. Address and user are kept in UserDefaults, the password in the
/// Keychain, under the same names the Swift Flaco used.
@interface FLServer : NSObject
@property (class, readonly) FLServer *shared;
@property (nonatomic, readonly) NSString *address, *user, *host;
@property (nonatomic, readonly) BOOL configured;
/// The Keychain outlives the app; a fresh install starts signed out.
- (void)clearIfFreshInstall;
/// Signs in without saving anything. Calls back on the main queue with nil, or what went wrong.
- (void)checkAddress:(NSString *)address user:(NSString *)user password:(NSString *)password
          completion:(void (^)(NSString *_Nullable error))completion;
- (void)saveAddress:(NSString *)address user:(NSString *)user password:(NSString *)password;
- (void)disconnect;
/// Every song on the server, and whether it's still scanning its folders.
- (void)listing:(void (^)(NSArray<FLSong *> *_Nullable songs, BOOL scanning, NSString *_Nullable error))completion;
- (nullable NSURL *)downloadURL:(NSString *)songID;
- (nullable NSURL *)coverURL:(NSString *)coverID size:(NSInteger)size;
@end

#pragma mark - Sync

typedef NS_ENUM(NSInteger, FLSyncPhase) { FLSyncIdle, FLSyncChecking, FLSyncDownloading, FLSyncFailed };
typedef NS_ENUM(NSInteger, FLChoice) { FLChoiceUndecided, FLChoiceEverything, FLChoiceChosen };

extern NSNotificationName const FLSyncDidChange;

/// An album on the server, as the chooser shows it.
@interface FLRemoteAlbum : NSObject
@property (nonatomic, copy) NSString *albumID, *title, *artist;
@property (nonatomic, copy, nullable) NSString *coverArt;
@property (nonatomic) NSInteger year;
@property (nonatomic) long long size;
@property (nonatomic, copy) NSArray<FLSong *> *songs;
@end

/// Keeps the phone's copy of the chosen music: downloads what's new or changed, removes what's gone from the
/// server or unticked. Only files that came from the server are ever removed; music added by hand stays.
/// Downloads run in a background session, so they carry on with Flaco closed.
@interface FLSync : NSObject
@property (class, readonly) FLSync *shared;
@property (nonatomic, readonly) FLSyncPhase phase;
@property (nonatomic, readonly, nullable) NSString *failure;
/// The server's albums at the last check, by artist.
@property (nonatomic, readonly) NSArray<FLRemoteAlbum *> *albums;
@property (nonatomic, readonly) FLChoice choice;
@property (nonatomic, readonly) long long bytesDone, bytesTotal;
@property (nonatomic, readonly) NSInteger filesDone, filesTotal;
/// Bytes a second over the last few seconds.
@property (nonatomic, readonly) double speed;
@property (nonatomic, readonly, nullable) NSDate *lastSynced;
@property (nonatomic, copy, nullable) void (^backgroundCompletion)(void);
- (BOOL)wants:(FLRemoteAlbum *)album;
- (BOOL)hasOnPhone:(FLRemoteAlbum *)album;
- (void)chooseEverything;
- (void)chooseAlbums:(NSSet<NSString *> *)albumIDs;
- (void)start;
/// Starts unless it's downloading already or checked in the last two minutes.
- (void)startIfDue;
/// Picks up downloads that ran while Flaco was closed.
- (void)reconnect;
- (void)forgetServer;
+ (long long)freeSpace;
+ (long long)capacity;
@end

/// Settings, over the player: the server, what comes down from it, and ReplayGain. `choosing` opens the album
/// chooser on top.
UIViewController *FLSettingsScreen(BOOL choosing);

NS_ASSUME_NONNULL_END

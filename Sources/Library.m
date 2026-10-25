#import "Flaco.h"
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <ImageIO/ImageIO.h>
#import "dr_flac.h"

NSNotificationName const FLLibraryDidChange = @"FLLibraryDidChange";

static NSString *FLHash(NSString *text) {
    uint64_t h = 0xcbf29ce484222325ULL;
    for (const char *c = text.UTF8String; *c; c++) { h ^= (uint8_t)*c; h *= 0x100000001b3ULL; }
    return [NSString stringWithFormat:@"%llx", h];
}

/// "The Quiet Field" sorts under Q.
static NSString *FLSortName(NSString *name) {
    NSString *lower = name.lowercaseString;
    return [lower hasPrefix:@"the "] ? [lower substringFromIndex:4] : lower;
}

#pragma mark - Track

@implementation FLTrack

- (instancetype)initWithDictionary:(NSDictionary *)d {
    if ((self = [super init])) {
        _path = d[@"path"]; _title = d[@"title"]; _artist = d[@"artist"]; _album = d[@"album"];
        _albumArtist = d[@"albumArtist"]; _format = d[@"format"];
        _number = [d[@"number"] integerValue]; _disc = [d[@"disc"] integerValue]; _year = [d[@"year"] integerValue];
        _bits = [d[@"bits"] integerValue]; _channels = [d[@"channels"] integerValue];
        _duration = [d[@"duration"] doubleValue]; _sampleRate = [d[@"sampleRate"] doubleValue];
        _modified = [d[@"modified"] doubleValue]; _size = [d[@"size"] longLongValue];
        _trackGain = d[@"trackGain"] ? [d[@"trackGain"] doubleValue] : NAN;
        _albumGain = d[@"albumGain"] ? [d[@"albumGain"] doubleValue] : NAN;
        _trackPeak = d[@"trackPeak"] ? [d[@"trackPeak"] doubleValue] : NAN;
        _albumPeak = d[@"albumPeak"] ? [d[@"albumPeak"] doubleValue] : NAN;
    }
    return self;
}

- (instancetype)init {
    if ((self = [super init])) _trackGain = _albumGain = _trackPeak = _albumPeak = NAN;
    return self;
}

- (NSDictionary *)dictionary {
    NSMutableDictionary *d = [@{@"path": _path, @"title": _title, @"artist": _artist, @"album": _album, @"albumArtist": _albumArtist,
             @"format": _format, @"number": @(_number), @"disc": @(_disc), @"year": @(_year), @"bits": @(_bits),
             @"channels": @(_channels), @"duration": @(_duration), @"sampleRate": @(_sampleRate),
             @"modified": @(_modified), @"size": @(_size)} mutableCopy];
    // A plist can't hold NAN, so missing tags are left out.
    if (!isnan(_trackGain)) d[@"trackGain"] = @(_trackGain);
    if (!isnan(_albumGain)) d[@"albumGain"] = @(_albumGain);
    if (!isnan(_trackPeak)) d[@"trackPeak"] = @(_trackPeak);
    if (!isnan(_albumPeak)) d[@"albumPeak"] = @(_albumPeak);
    return d;
}

- (NSURL *)url { return [FLLibrary.documents URLByAppendingPathComponent:_path]; }

- (NSString *)albumKey { return [NSString stringWithFormat:@"%@\n%@", _albumArtist.lowercaseString, _album.lowercaseString]; }

- (NSString *)status {
    NSMutableArray *parts = [NSMutableArray arrayWithObject:_format];
    if (_duration > 0) [parts addObject:[NSString stringWithFormat:@"%.0f kbps", _size * 8 / _duration / 1000]];
    if (_sampleRate > 0) {
        double k = _sampleRate / 1000;
        [parts addObject:[NSString stringWithFormat:(fmod(k, 1) == 0 ? @"%.0f kHz" : @"%.1f kHz"), k]];
    }
    if (_bits > 0) [parts addObject:[NSString stringWithFormat:@"%ld bit", (long)_bits]];
    return [parts componentsJoinedByString:@" | "];
}

- (BOOL)isEqual:(id)other { return [other isKindOfClass:FLTrack.class] && [((FLTrack *)other).path isEqualToString:_path]; }
- (NSUInteger)hash { return _path.hash; }

@end

#pragma mark - Album

@implementation FLAlbum
- (double)duration { return [[_tracks valueForKeyPath:@"@sum.duration"] doubleValue]; }
- (long long)size { return [[_tracks valueForKeyPath:@"@sum.size"] longLongValue]; }
@end

#pragma mark - Reading files

/// What a FLAC's metadata blocks hold, gathered by dr_flac's callback.
typedef struct {
    __unsafe_unretained NSMutableDictionary *tags;
    __unsafe_unretained NSMutableData *cover;
    int coverType;
} FLMeta;

static void FLOnMeta(void *user, drflac_metadata *m) {
    FLMeta *meta = user;
    if (m->type == DRFLAC_METADATA_BLOCK_TYPE_VORBIS_COMMENT) {
        drflac_vorbis_comment_iterator it;
        drflac_init_vorbis_comment_iterator(&it, m->data.vorbis_comment.commentCount, m->data.vorbis_comment.pComments);
        drflac_uint32 length;
        const char *comment;
        while ((comment = drflac_next_vorbis_comment(&it, &length))) {
            NSString *line = [[NSString alloc] initWithBytes:comment length:length encoding:NSUTF8StringEncoding];
            NSRange eq = [line rangeOfString:@"="];
            if (!line || eq.location == NSNotFound) continue;
            NSString *key = [line substringToIndex:eq.location].uppercaseString;
            if (!meta->tags[key]) meta->tags[key] = [line substringFromIndex:eq.location + 1];
        }
    } else if (m->type == DRFLAC_METADATA_BLOCK_TYPE_PICTURE && m->data.picture.pPictureData) {
        // The front cover wins over any other picture.
        int type = (int)m->data.picture.type;
        if (meta->cover.length == 0 || (type == DRFLAC_PICTURE_TYPE_COVER_FRONT && meta->coverType != DRFLAC_PICTURE_TYPE_COVER_FRONT)) {
            [meta->cover setData:[NSData dataWithBytes:m->data.picture.pPictureData length:m->data.picture.pictureDataSize]];
            meta->coverType = type;
        }
    }
}

static NSInteger FLLeadingNumber(NSString *text) {
    return text.length ? [[text componentsSeparatedByString:@"/"].firstObject integerValue] : 0;
}

/// Reads a file's tags, filling what's missing from its name and folder. Returns its cover too, if it has one.
static FLTrack *FLRead(NSURL *url, NSString *path, NSData *__autoreleasing *coverOut) {
    FLTrack *track = [FLTrack new];
    track.path = path;
    NSMutableDictionary *tags = [NSMutableDictionary dictionary];
    NSMutableData *cover = [NSMutableData data];
    NSString *ext = url.pathExtension.lowercaseString;

    if ([ext isEqualToString:@"flac"]) {
        FLMeta meta = {tags, cover, -1};
        drflac *flac = drflac_open_file_with_metadata(url.fileSystemRepresentation, FLOnMeta, &meta, NULL);
        if (!flac) return nil;
        track.sampleRate = flac->sampleRate;
        track.channels = flac->channels;
        track.bits = flac->bitsPerSample;
        track.duration = flac->sampleRate ? (double)flac->totalPCMFrameCount / flac->sampleRate : 0;
        drflac_close(flac);
        track.format = @"FLAC";
        track.title = tags[@"TITLE"];
        track.artist = tags[@"ARTIST"];
        track.album = tags[@"ALBUM"];
        track.albumArtist = tags[@"ALBUMARTIST"] ?: tags[@"ALBUM ARTIST"];
        track.number = FLLeadingNumber(tags[@"TRACKNUMBER"]);
        track.disc = FLLeadingNumber(tags[@"DISCNUMBER"]);
        NSString *date = tags[@"DATE"] ?: tags[@"YEAR"] ?: @"";
        track.year = [[date substringToIndex:MIN(4, date.length)] integerValue];
        // "-6.54 dB" and "0.988"; doubleValue reads the number and stops.
        if (tags[@"REPLAYGAIN_TRACK_GAIN"]) track.trackGain = [tags[@"REPLAYGAIN_TRACK_GAIN"] doubleValue];
        if (tags[@"REPLAYGAIN_ALBUM_GAIN"]) track.albumGain = [tags[@"REPLAYGAIN_ALBUM_GAIN"] doubleValue];
        if (tags[@"REPLAYGAIN_TRACK_PEAK"]) track.trackPeak = [tags[@"REPLAYGAIN_TRACK_PEAK"] doubleValue];
        if (tags[@"REPLAYGAIN_ALBUM_PEAK"]) track.albumPeak = [tags[@"REPLAYGAIN_ALBUM_PEAK"] doubleValue];
    } else {
        AudioFileID file = NULL;
        if (AudioFileOpenURL((__bridge CFURLRef)url, kAudioFileReadPermission, 0, &file) != noErr) return nil;
        AudioStreamBasicDescription format = {0};
        UInt32 size = sizeof(format);
        AudioFileGetProperty(file, kAudioFilePropertyDataFormat, &size, &format);
        Float64 duration = 0;
        size = sizeof(duration);
        AudioFileGetProperty(file, kAudioFilePropertyEstimatedDuration, &size, &duration);
        UInt32 bits = 0;
        size = sizeof(bits);
        AudioFileGetProperty(file, kAudioFilePropertySourceBitDepth, &size, &bits);
        CFDictionaryRef info = NULL;
        size = sizeof(info);
        if (AudioFileGetProperty(file, kAudioFilePropertyInfoDictionary, &size, &info) == noErr && info) {
            NSDictionary *d = (__bridge_transfer NSDictionary *)info;
            track.title = d[@kAFInfoDictionary_Title];
            track.artist = d[@kAFInfoDictionary_Artist];
            track.album = d[@kAFInfoDictionary_Album];
            track.number = FLLeadingNumber(d[@kAFInfoDictionary_TrackNumber]);
            track.year = [d[@kAFInfoDictionary_Year] integerValue];
        }
        AudioFileClose(file);
        track.sampleRate = format.mSampleRate;
        track.channels = format.mChannelsPerFrame;
        track.bits = bits;
        track.duration = duration;
        NSDictionary *names = @{@"mp3": @"MP3", @"m4a": @"M4A", @"aac": @"AAC", @"wav": @"WAV", @"aif": @"AIFF", @"aiff": @"AIFF", @"caf": @"CAF"};
        track.format = format.mFormatID == kAudioFormatAppleLossless ? @"ALAC" : names[ext] ?: ext.uppercaseString;
        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
        for (AVMetadataItem *item in [AVMetadataItem metadataItemsFromArray:asset.commonMetadata withKey:AVMetadataCommonKeyArtwork keySpace:AVMetadataKeySpaceCommon]) {
            if (item.dataValue.length) { [cover setData:item.dataValue]; break; }
        }
    }

    // Gaps filled from "Artist - Album/01 Title.flac".
    NSString *folder = path.stringByDeletingLastPathComponent.lastPathComponent;
    NSArray *folderParts = [folder componentsSeparatedByString:@" - "];
    NSString *name = path.lastPathComponent.stringByDeletingPathExtension;
    if (!track.title.length) {
        NSRegularExpression *lead = [NSRegularExpression regularExpressionWithPattern:@"^\\d+[\\s.\\-_]*" options:0 error:nil];
        track.title = [lead stringByReplacingMatchesInString:name options:0 range:NSMakeRange(0, name.length) withTemplate:@""];
        if (!track.title.length) track.title = name;
    }
    if (!track.album.length) track.album = folderParts.count == 2 ? folderParts[1] : (folder.length ? folder : @"Unknown album");
    if (!track.artist.length) track.artist = folderParts.count == 2 ? folderParts[0] : @"Unknown artist";
    if (!track.albumArtist.length) track.albumArtist = track.artist;
    if (track.number == 0) track.number = [name integerValue];
    if (coverOut) *coverOut = cover.length ? cover : nil;
    return track;
}

#pragma mark - Library

@interface FLLibrary ()
@property (nonatomic, readwrite) NSArray<FLAlbum *> *albums;
@property (nonatomic, readwrite) NSArray<FLTrack *> *tracks;
@property (nonatomic, readwrite) BOOL scanning;
@end

@implementation FLLibrary {
    dispatch_queue_t _queue;
    NSDictionary<NSString *, FLTrack *> *_byPath;
    NSDictionary<NSString *, FLAlbum *> *_albumByKey;
    NSMutableDictionary<NSString *, FLTheme *> *_palettes;
    NSCache<NSString *, UIImage *> *_images;
    BOOL _again;
}

+ (FLLibrary *)shared {
    static FLLibrary *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [FLLibrary new]; });
    return shared;
}

+ (NSURL *)documents {
    return [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
}

+ (NSURL *)caches {
    NSURL *url = [[NSFileManager.defaultManager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject URLByAppendingPathComponent:@"Flaco"];
    [NSFileManager.defaultManager createDirectoryAtURL:[url URLByAppendingPathComponent:@"Covers"] withIntermediateDirectories:YES attributes:nil error:nil];
    return url;
}

- (instancetype)init {
    if ((self = [super init])) {
        _queue = dispatch_queue_create("flaco.library", DISPATCH_QUEUE_SERIAL);
        _albums = @[];
        _tracks = @[];
        _byPath = @{};
        _albumByKey = @{};
        _palettes = [NSMutableDictionary dictionary];
        _images = [NSCache new];
        _images.countLimit = 60;
    }
    return self;
}

- (NSURL *)indexURL { return [FLLibrary.caches URLByAppendingPathComponent:@"index.plist"]; }
- (NSURL *)palettesURL { return [FLLibrary.caches URLByAppendingPathComponent:@"palettes.plist"]; }

- (void)load {
    NSDictionary *palettes = [NSDictionary dictionaryWithContentsOfURL:self.palettesURL];
    [palettes enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSArray *hexes, BOOL *stop) {
        self->_palettes[key] = [[FLTheme alloc] initWithArray:hexes];
    }];
    NSMutableArray *tracks = [NSMutableArray array];
    for (NSDictionary *d in [NSArray arrayWithContentsOfURL:self.indexURL]) [tracks addObject:[[FLTrack alloc] initWithDictionary:d]];
    [self publish:tracks];
}

- (void)scan {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.scanning) { self->_again = YES; return; }
        self.scanning = YES;
        NSDictionary *known = self->_byPath;
        NSDictionary *palettes = [self->_palettes copy];
        dispatch_async(self->_queue, ^{ [self scanKnowing:known palettes:palettes]; });
    });
}

- (void)scanKnowing:(NSDictionary<NSString *, FLTrack *> *)known palettes:(NSDictionary<NSString *, FLTheme *> *)knownPalettes {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSSet *audio = [NSSet setWithObjects:@"flac", @"mp3", @"m4a", @"aac", @"wav", @"aif", @"aiff", @"caf", nil];
    NSURL *documents = FLLibrary.documents;
    NSString *base = documents.URLByStandardizingPath.path;
    NSMutableArray<FLTrack *> *found = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSData *> *covers = [NSMutableDictionary dictionary];
    NSDirectoryEnumerator *walker = [fm enumeratorAtURL:documents includingPropertiesForKeys:@[NSURLFileSizeKey, NSURLContentModificationDateKey]
                                                options:NSDirectoryEnumerationSkipsHiddenFiles errorHandler:nil];
    for (NSURL *url in walker) {
        if ([url.lastPathComponent isEqualToString:@"Inbox"]) { [walker skipDescendants]; continue; }
        if (![audio containsObject:url.pathExtension.lowercaseString]) continue;
        NSNumber *size; NSDate *date;
        [url getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
        [url getResourceValue:&date forKey:NSURLContentModificationDateKey error:nil];
        NSString *full = url.URLByStandardizingPath.path;
        NSString *path = [full hasPrefix:[base stringByAppendingString:@"/"]] ? [full substringFromIndex:base.length + 1] : url.lastPathComponent;
        FLTrack *old = known[path];
        if (old && old.size == size.longLongValue && old.modified == date.timeIntervalSince1970) { [found addObject:old]; continue; }
        // Finder may still be copying it; the next scan takes it.
        if (NSDate.date.timeIntervalSince1970 - date.timeIntervalSince1970 < 3) { _again = YES; continue; }
        @autoreleasepool {
            NSData *cover = nil;
            FLTrack *track = FLRead(url, path, &cover);
            if (!track) continue;
            track.size = size.longLongValue;
            track.modified = date.timeIntervalSince1970;
            [found addObject:track];
            if (cover && !covers[track.albumKey]) covers[track.albumKey] = cover;
        }
    }

    // A cover and a palette for every album that has none yet.
    NSMutableDictionary *palettes = [knownPalettes mutableCopy];
    NSMutableSet *seen = [NSMutableSet set];
    for (FLTrack *track in found) {
        NSString *key = track.albumKey;
        if ([seen containsObject:key]) continue;
        [seen addObject:key];
        NSString *name = FLHash(key);
        NSURL *small = [[FLLibrary.caches URLByAppendingPathComponent:@"Covers"] URLByAppendingPathComponent:[name stringByAppendingString:@"-s.jpg"]];
        if (![fm fileExistsAtPath:small.path]) {
            NSData *data = covers[key] ?: [self folderImageNear:track.url];
            if (data) [self storeCover:data name:name];
        }
        if (!palettes[name]) {
            UIImage *image = [UIImage imageWithContentsOfFile:small.path];
            if (image) palettes[name] = [FLTheme paletteFromImage:image];
        }
    }

    [[found valueForKey:@"dictionary"] writeToURL:self.indexURL atomically:YES];
    NSMutableDictionary *plist = [NSMutableDictionary dictionary];
    [palettes enumerateKeysAndObjectsUsingBlock:^(NSString *key, FLTheme *theme, BOOL *stop) { plist[key] = theme.array; }];
    [plist writeToURL:self.palettesURL atomically:YES];

    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_palettes setDictionary:palettes];
        self.scanning = NO;
        [self publish:found];
        if (self->_again) {
            self->_again = NO;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 4 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ [self scan]; });
        }
    });
}

/// cover.jpg, folder.jpg and the like beside the song.
- (NSData *)folderImageNear:(NSURL *)url {
    NSArray *items = [NSFileManager.defaultManager contentsOfDirectoryAtURL:url.URLByDeletingLastPathComponent includingPropertiesForKeys:nil options:0 error:nil];
    NSURL *chosen = nil;
    for (NSURL *item in items) {
        NSString *ext = item.pathExtension.lowercaseString;
        if (![ext isEqualToString:@"jpg"] && ![ext isEqualToString:@"jpeg"] && ![ext isEqualToString:@"png"]) continue;
        NSString *name = item.URLByDeletingPathExtension.lastPathComponent.lowercaseString;
        if ([@[@"cover", @"folder", @"front", @"albumart", @"album"] containsObject:name]) { chosen = item; break; }
        if (!chosen) chosen = item;
    }
    return chosen ? [NSData dataWithContentsOfURL:chosen] : nil;
}

/// Scaled with ImageIO, which never decodes the full image: covers can be 3000 pixels and the 5c has 1 GB.
- (void)storeCover:(NSData *)data name:(NSString *)name {
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    if (!source) return;
    NSURL *folder = [FLLibrary.caches URLByAppendingPathComponent:@"Covers"];
    for (NSArray *size in @[@[@"s", @180], @[@"l", @600]]) {
        NSDictionary *options = @{(id)kCGImageSourceCreateThumbnailFromImageAlways: @YES, (id)kCGImageSourceThumbnailMaxPixelSize: size[1],
                                  (id)kCGImageSourceCreateThumbnailWithTransform: @YES};
        CGImageRef image = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options);
        if (!image) continue;
        NSData *jpeg = UIImageJPEGRepresentation([UIImage imageWithCGImage:image], 0.85);
        CGImageRelease(image);
        [jpeg writeToURL:[folder URLByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@.jpg", name, size[0]]] atomically:YES];
    }
    CFRelease(source);
}

- (void)publish:(NSArray<FLTrack *> *)list {
    NSMutableDictionary<NSString *, NSMutableArray<FLTrack *> *> *grouped = [NSMutableDictionary dictionary];
    for (FLTrack *track in list) {
        if (!grouped[track.albumKey]) grouped[track.albumKey] = [NSMutableArray array];
        [grouped[track.albumKey] addObject:track];
    }
    NSMutableArray<FLAlbum *> *albums = [NSMutableArray array];
    [grouped enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSMutableArray<FLTrack *> *tracks, BOOL *stop) {
        [tracks sortUsingComparator:^NSComparisonResult(FLTrack *a, FLTrack *b) {
            if (a.disc != b.disc) return a.disc < b.disc ? NSOrderedAscending : NSOrderedDescending;
            if (a.number != b.number) return a.number < b.number ? NSOrderedAscending : NSOrderedDescending;
            return [a.path compare:b.path];
        }];
        FLAlbum *album = [FLAlbum new];
        album.key = key;
        album.title = tracks[0].album;
        album.artist = tracks[0].albumArtist;
        album.tracks = tracks;
        album.coverID = FLHash(key);
        for (FLTrack *t in tracks) if (t.year) { album.year = t.year; break; }
        [albums addObject:album];
    }];
    [albums sortUsingComparator:^NSComparisonResult(FLAlbum *a, FLAlbum *b) {
        NSComparisonResult byArtist = [FLSortName(a.artist) compare:FLSortName(b.artist)];
        if (byArtist != NSOrderedSame) return byArtist;
        if (a.year != b.year) return a.year < b.year ? NSOrderedAscending : NSOrderedDescending;
        return [a.title localizedCaseInsensitiveCompare:b.title];
    }];
    NSMutableArray *tracks = [NSMutableArray array];
    NSMutableDictionary *byPath = [NSMutableDictionary dictionary], *byKey = [NSMutableDictionary dictionary];
    for (FLAlbum *album in albums) {
        [tracks addObjectsFromArray:album.tracks];
        byKey[album.key] = album;
        for (FLTrack *t in album.tracks) byPath[t.path] = t;
    }
    self.albums = albums;
    self.tracks = tracks;
    _byPath = byPath;
    _albumByKey = byKey;
    [NSNotificationCenter.defaultCenter postNotificationName:FLLibraryDidChange object:self];
}

- (FLTrack *)trackAtPath:(NSString *)path { return _byPath[path]; }
- (FLAlbum *)albumForTrack:(FLTrack *)track { return _albumByKey[track.albumKey]; }

- (UIImage *)coverForAlbum:(FLAlbum *)album large:(BOOL)large {
    NSString *name = [NSString stringWithFormat:@"%@-%@.jpg", album.coverID, large ? @"l" : @"s"];
    UIImage *image = [_images objectForKey:name];
    if (!image) {
        image = [UIImage imageWithContentsOfFile:[[FLLibrary.caches URLByAppendingPathComponent:@"Covers"] URLByAppendingPathComponent:name].path];
        if (image) [_images setObject:image forKey:name];
    }
    return image;
}

- (FLTheme *)themeForTrack:(FLTrack *)track {
    FLAlbum *album = track ? [self albumForTrack:track] : nil;
    return (album ? _palettes[album.coverID] : nil) ?: FLTheme.neutral;
}

@end

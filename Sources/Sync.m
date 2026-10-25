#import "Flaco.h"

NSNotificationName const FLSyncDidChange = @"FLSyncDidChange";

@implementation FLRemoteAlbum
@end

/// What a download is for, carried in the task's description so it survives a relaunch: "id\nsize\npath".
static BOOL FLJobOf(NSURLSessionTask *task, NSString **songID, long long *size, NSString **path) {
    NSArray *parts = [task.taskDescription componentsSeparatedByString:@"\n"];
    if (parts.count < 3) return NO;
    *songID = parts[0];
    *size = [parts[1] longLongValue];
    *path = [[parts subarrayWithRange:NSMakeRange(2, parts.count - 2)] componentsJoinedByString:@"\n"];
    return YES;
}

static NSString *FLSortKey(NSString *name) {
    NSString *lower = name.lowercaseString;
    return [lower hasPrefix:@"the "] ? [lower substringFromIndex:4] : lower;
}

@interface FLSync () <NSURLSessionDownloadDelegate>
@property (nonatomic, readwrite) FLSyncPhase phase;
@property (nonatomic, readwrite, nullable) NSString *failure;
@property (nonatomic, readwrite) NSArray<FLRemoteAlbum *> *albums;
@property (nonatomic, readwrite) FLChoice choice;
@property (nonatomic, readwrite) long long bytesTotal;
@property (nonatomic, readwrite) NSInteger filesDone, filesTotal;
@property (nonatomic, readwrite) double speed;
@property (nonatomic, readwrite, nullable) NSDate *lastSynced;
@end

@implementation FLSync {
    NSURLSession *_session;
    NSArray<FLSong *> *_catalog;
    /// Files the server gave us, by song id: {path, size}. The same file the Swift Flaco kept.
    NSMutableDictionary<NSString *, NSDictionary *> *_manifest;
    /// Ticked albums, and the finer choices the Swift Flaco could make, kept until the next choice.
    NSMutableSet<NSString *> *_albumIDs, *_artists, *_songIDs;
    NSMutableSet<NSString *> *_active, *_broken;
    NSMutableDictionary<NSString *, NSNumber *> *_written;
    NSMutableArray<NSArray<NSNumber *> *> *_samples;
    long long _bytesFinished;
    NSInteger _failed;
    CFAbsoluteTime _lastCheck, _lastScan, _lastNotice;
    BOOL _scanPending, _noticePending;
}

+ (FLSync *)shared {
    static FLSync *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [FLSync new]; });
    return shared;
}

+ (NSURL *)support {
    NSURL *url = [[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject
                  URLByAppendingPathComponent:@"Flaco"];
    [NSFileManager.defaultManager createDirectoryAtURL:url withIntermediateDirectories:YES attributes:nil error:nil];
    return url;
}

- (NSURL *)manifestURL { return [FLSync.support URLByAppendingPathComponent:@"sync.json"]; }
- (NSURL *)catalogURL { return [FLSync.support URLByAppendingPathComponent:@"catalog.json"]; }

- (instancetype)init {
    if (!(self = [super init])) return nil;
    NSString *identifier = [NSBundle.mainBundle.bundleIdentifier ?: @"flaco" stringByAppendingString:@".sync"];
#if TARGET_OS_SIMULATOR
    // The simulator's download daemon fails every task of an app without a team signature, so it downloads in
    // the foreground there; phones are signed with the team and download in the background.
    NSURLSessionConfiguration *config = NSURLSessionConfiguration.defaultSessionConfiguration;
    (void)identifier;
#else
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration backgroundSessionConfigurationWithIdentifier:identifier];
#endif
    config.allowsCellularAccess = NO;
#if !TARGET_OS_SIMULATOR
    config.sessionSendsLaunchEvents = YES;
#endif
    _session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:NSOperationQueue.mainQueue];
    _active = [NSMutableSet set];
    _broken = [NSMutableSet set];
    _written = [NSMutableDictionary dictionary];
    _samples = [NSMutableArray array];

    NSDictionary *manifest = [self readJSON:self.manifestURL];
    _manifest = [manifest isKindOfClass:NSDictionary.class] ? [manifest mutableCopy] : [NSMutableDictionary dictionary];
    NSArray *catalog = [self readJSON:self.catalogURL];
    NSMutableArray *songs = [NSMutableArray array];
    if ([catalog isKindOfClass:NSArray.class]) for (NSDictionary *d in catalog) [songs addObject:[[FLSong alloc] initWithDictionary:d]];
    _catalog = songs;
    [self groupAlbums];

    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    _lastSynced = [defaults objectForKey:@"syncLast"];
    NSData *saved = [defaults dataForKey:@"syncSelection"];
    NSDictionary *selection = saved ? [NSJSONSerialization JSONObjectWithData:saved options:0 error:nil] : nil;
    _albumIDs = [NSMutableSet setWithArray:selection[@"albums"] ?: @[]];
    _artists = [NSMutableSet setWithArray:selection[@"artists"] ?: @[]];
    _songIDs = [NSMutableSet setWithArray:selection[@"songs"] ?: @[]];
    NSString *mode = selection[@"mode"];
    if ([mode isEqual:@"everything"]) _choice = FLChoiceEverything;
    else if ([mode isEqual:@"chosen"]) _choice = FLChoiceChosen;
    else _choice = FLChoiceUndecided;
    return self;
}

- (id)readJSON:(NSURL *)url {
    NSData *data = [NSData dataWithContentsOfURL:url];
    return data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
}

- (void)writeJSON:(id)object to:(NSURL *)url {
    [[NSJSONSerialization dataWithJSONObject:object options:0 error:nil] writeToURL:url atomically:YES];
}

#pragma mark Choosing

- (BOOL)wantsSong:(FLSong *)song {
    switch (_choice) {
        case FLChoiceEverything: return YES;
        case FLChoiceChosen: return [_albumIDs containsObject:song.albumID] || [_artists containsObject:song.albumArtist] || [_songIDs containsObject:song.songID];
        case FLChoiceUndecided: return NO;
    }
}

- (BOOL)wants:(FLRemoteAlbum *)album {
    for (FLSong *song in album.songs) if ([self wantsSong:song]) return YES;
    return NO;
}

- (BOOL)hasOnPhone:(FLRemoteAlbum *)album {
    for (FLSong *song in album.songs) if (_manifest[song.songID]) return YES;
    return NO;
}

- (void)chooseEverything {
    self.choice = FLChoiceEverything;
    [_albumIDs removeAllObjects];
    [self saveChoice];
    [self start];
}

- (void)chooseAlbums:(NSSet<NSString *> *)albumIDs {
    self.choice = FLChoiceChosen;
    [_albumIDs setSet:albumIDs];
    [_artists removeAllObjects];
    [_songIDs removeAllObjects];
    [self saveChoice];
    [self start];
}

/// The Swift Flaco's format, so either app reads what the other wrote.
- (void)saveChoice {
    NSString *mode = _choice == FLChoiceEverything ? @"everything" : _choice == FLChoiceChosen ? @"chosen" : @"undecided";
    NSDictionary *selection = @{@"mode": mode, @"albums": _albumIDs.allObjects, @"artists": _artists.allObjects, @"songs": _songIDs.allObjects};
    [NSUserDefaults.standardUserDefaults setObject:[NSJSONSerialization dataWithJSONObject:selection options:0 error:nil] forKey:@"syncSelection"];
}

- (void)groupAlbums {
    NSMutableDictionary<NSString *, NSMutableArray<FLSong *> *> *grouped = [NSMutableDictionary dictionary];
    NSMutableArray<NSString *> *order = [NSMutableArray array];
    for (FLSong *song in _catalog) {
        NSString *key = song.albumID.length ? song.albumID : [NSString stringWithFormat:@"%@\n%@", song.albumArtist, song.album];
        if (!grouped[key]) {
            grouped[key] = [NSMutableArray array];
            [order addObject:key];
        }
        [grouped[key] addObject:song];
    }
    NSMutableArray<FLRemoteAlbum *> *albums = [NSMutableArray array];
    for (NSString *key in order) {
        NSArray<FLSong *> *songs = grouped[key];
        FLRemoteAlbum *album = [FLRemoteAlbum new];
        album.albumID = songs[0].albumID;
        album.title = songs[0].album.length ? songs[0].album : @"Unknown album";
        album.artist = songs[0].albumArtist.length ? songs[0].albumArtist : @"Unknown artist";
        album.songs = songs;
        long long size = 0;
        for (FLSong *song in songs) {
            size += song.size;
            album.year = MAX(album.year, song.year);
            if (!album.coverArt) album.coverArt = song.coverArt;
        }
        album.size = size;
        [albums addObject:album];
    }
    [albums sortUsingComparator:^NSComparisonResult(FLRemoteAlbum *a, FLRemoteAlbum *b) {
        NSComparisonResult byArtist = [FLSortKey(a.artist) compare:FLSortKey(b.artist)];
        if (byArtist != NSOrderedSame) return byArtist;
        if (a.year != b.year) return a.year < b.year ? NSOrderedAscending : NSOrderedDescending;
        return [a.title localizedCaseInsensitiveCompare:b.title];
    }];
    self.albums = albums;
}

#pragma mark Syncing

- (long long)bytesDone {
    long long done = _bytesFinished;
    for (NSNumber *written in _written.allValues) done += written.longLongValue;
    return done;
}

- (void)startIfDue {
    if (_phase == FLSyncDownloading || CFAbsoluteTimeGetCurrent() - _lastCheck < 120) return;
    [self start];
}

- (void)start {
    if (!FLServer.shared.configured || _phase == FLSyncChecking) return;
    BOOL downloading = _phase == FLSyncDownloading;
    if (!downloading) {
        self.phase = FLSyncChecking;
        [self notify];
    }
    _lastCheck = CFAbsoluteTimeGetCurrent();
    [FLServer.shared listing:^(NSArray<FLSong *> *songs, BOOL scanning, NSString *error) {
        if (error) {
            if (!downloading) {
                self.failure = error;
                self.phase = FLSyncFailed;
            }
            [self notify];
            return;
        }
        [self->_session getTasksWithCompletionHandler:^(NSArray *data, NSArray *uploads, NSArray *downloads) {
            dispatch_async(dispatch_get_main_queue(), ^{ [self plan:songs scanning:scanning running:downloads]; });
        }];
    }];
}

- (void)plan:(NSArray<FLSong *> *)listing scanning:(BOOL)scanning running:(NSArray<NSURLSessionTask *> *)tasks {
    NSArray<FLSong *> *songs = [listing sortedArrayUsingComparator:^NSComparisonResult(FLSong *a, FLSong *b) {
        return [a.path localizedStandardCompare:b.path];
    }];
    _catalog = songs;
    [self writeJSON:[songs valueForKey:@"dictionary"] to:self.catalogURL];
    [self groupAlbums];

    // A server that lists nothing, or is mid-scan, may be wrong about what's gone. Unticked songs go
    // regardless, once something has been chosen.
    BOOL trusted = songs.count > 0 && !scanning;
    NSMutableDictionary<NSString *, FLSong *> *remote = [NSMutableDictionary dictionary];
    for (FLSong *song in songs) if (!remote[song.songID]) remote[song.songID] = song;
    NSInteger removed = 0;
    for (NSString *songID in _manifest.allKeys) {
        NSDictionary *entry = _manifest[songID];
        FLSong *song = remote[songID];
        BOOL gone = trusted && ![song.path isEqualToString:entry[@"path"]];
        BOOL unticked = _choice != FLChoiceUndecided && song && ![self wantsSong:song];
        if (!gone && !unticked) continue;
        [self removeFile:entry[@"path"]];
        [_manifest removeObjectForKey:songID];
        removed++;
    }

    NSMutableArray<FLSong *> *wanted = [NSMutableArray array];
    NSURL *documents = FLLibrary.documents;
    for (FLSong *song in songs) {
        if (![self wantsSong:song]) continue;
        NSNumber *size = [NSFileManager.defaultManager attributesOfItemAtPath:[documents URLByAppendingPathComponent:song.path].path error:nil][NSFileSize];
        if (size && size.longLongValue == song.size) {
            // Already here, from an earlier sync or copied by hand.
            _manifest[song.songID] = @{@"path": song.path, @"size": @(song.size)};
        } else {
            [_manifest removeObjectForKey:song.songID];
            [wanted addObject:song];
        }
    }
    [self saveManifest];
    _failed = 0;
    [_broken removeAllObjects];
    if (removed) [self scanSoon:YES];

    NSMutableSet *wantedIDs = [NSMutableSet setWithArray:[wanted valueForKey:@"songID"]], *running = [NSMutableSet set];
    for (NSURLSessionTask *task in tasks) {
        NSString *songID, *path;
        long long size;
        if (!FLJobOf(task, &songID, &size, &path)) continue;
        if ([wantedIDs containsObject:songID]) [running addObject:songID];
        else [task cancel];
    }
    long long needed = 0, total = 0;
    for (FLSong *song in wanted) {
        total += song.size;
        if (![running containsObject:song.songID]) needed += song.size;
    }
    long long free = FLSync.freeSpace;
    if (needed > 0 && needed + 300000000 > free) {
        self.failure = [NSString stringWithFormat:@"Needs %@, %@ free.", FLSize(needed), FLSize(free)];
        self.phase = FLSyncFailed;
        [self notify];
        return;
    }

    for (FLSong *song in wanted) {
        if ([running containsObject:song.songID]) continue;
        NSURL *url = [FLServer.shared downloadURL:song.songID];
        if (!url) continue;
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
        request.allowsCellularAccess = NO;
        NSURLSessionDownloadTask *task = [_session downloadTaskWithRequest:request];
        task.taskDescription = [NSString stringWithFormat:@"%@\n%lld\n%@", song.songID, song.size, song.path];
        [task resume];
    }
    [_active setSet:wantedIDs];
    [_written removeAllObjects];
    [_samples removeAllObjects];
    _bytesFinished = 0;
    self.filesDone = 0;
    self.filesTotal = wanted.count;
    self.bytesTotal = total;
    if (wanted.count == 0) {
        [self finish];
    } else {
        self.failure = nil;
        self.phase = FLSyncDownloading;
        [self notify];
    }
}

- (void)finish {
    [self saveManifest];
    [self scanSoon:YES];
    [_samples removeAllObjects];
    self.speed = 0;
    if (_failed) {
        self.failure = _failed == 1 ? @"1 song didn't download." : [NSString stringWithFormat:@"%ld songs didn't download.", (long)_failed];
        self.phase = FLSyncFailed;
    } else {
        self.failure = nil;
        self.phase = FLSyncIdle;
        self.lastSynced = NSDate.date;
        [NSUserDefaults.standardUserDefaults setObject:self.lastSynced forKey:@"syncLast"];
    }
    [self notify];
}

- (void)reconnect {
    [_session getTasksWithCompletionHandler:^(NSArray *data, NSArray *uploads, NSArray *downloads) {
        dispatch_async(dispatch_get_main_queue(), ^{
            long long total = 0;
            for (NSURLSessionTask *task in downloads) {
                NSString *songID, *path;
                long long size;
                if (task.state != NSURLSessionTaskStateRunning || !FLJobOf(task, &songID, &size, &path)) continue;
                [self->_active addObject:songID];
                self->_written[songID] = @(task.countOfBytesReceived);
                total += size;
            }
            if (!self->_active.count) return;
            self.bytesTotal = total;
            self.filesTotal = self->_active.count;
            self.phase = FLSyncDownloading;
            [self notify];
        });
    }];
}

- (void)forgetServer {
    [_session getTasksWithCompletionHandler:^(NSArray *data, NSArray *uploads, NSArray *downloads) {
        for (NSURLSessionTask *task in downloads) [task cancel];
    }];
    // What came down stays, as if copied by hand.
    [_manifest removeAllObjects];
    [self saveManifest];
    _catalog = @[];
    self.albums = @[];
    [NSFileManager.defaultManager removeItemAtURL:self.catalogURL error:nil];
    self.choice = FLChoiceUndecided;
    [_albumIDs removeAllObjects];
    [_artists removeAllObjects];
    [_songIDs removeAllObjects];
    [_active removeAllObjects];
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults removeObjectForKey:@"syncSelection"];
    [defaults removeObjectForKey:@"syncLast"];
    self.lastSynced = nil;
    self.failure = nil;
    self.phase = FLSyncIdle;
    [self notify];
}

#pragma mark Downloads

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)task didWriteData:(int64_t)bytesWritten
    totalBytesWritten:(int64_t)totalBytesWritten totalBytesExpectedToWrite:(int64_t)expected {
    NSString *songID, *path;
    long long size;
    if (!FLJobOf(task, &songID, &size, &path) || ![_active containsObject:songID]) return;
    _written[songID] = @(totalBytesWritten);
    [self sample];
    [self notify];
}

/// The file has to be moved before this returns.
- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)task didFinishDownloadingToURL:(NSURL *)location {
    NSString *songID, *path;
    long long size;
    if (!FLJobOf(task, &songID, &size, &path)) return;
    NSInteger status = [task.response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)task.response).statusCode : 0;
    long long got = [[NSFileManager.defaultManager attributesOfItemAtPath:location.path error:nil][NSFileSize] longLongValue];
    if (status != 200 || (size > 0 && got != size)) {
        NSLog(@"sync: %@ came back as HTTP %ld, %lld of %lld bytes", path, (long)status, got, size);
        [_broken addObject:songID];
        return;
    }
    NSFileManager *fm = NSFileManager.defaultManager;
    NSURL *target = [FLLibrary.documents URLByAppendingPathComponent:path];
    [fm createDirectoryAtURL:target.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    [fm removeItemAtURL:target error:nil];
    NSError *moveError = nil;
    if ([fm moveItemAtURL:location toURL:target error:&moveError]) {
        _manifest[songID] = @{@"path": path, @"size": @(got)};
        [self saveManifest];
    } else {
        NSLog(@"sync: %@ couldn't be moved into place: %@", path, moveError.localizedDescription);
        [_broken addObject:songID];
    }
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    NSString *songID, *path;
    long long size;
    if (!FLJobOf(task, &songID, &size, &path) || ![_active containsObject:songID]) return;
    [_written removeObjectForKey:songID];
    [_active removeObject:songID];
    if (error || [_broken containsObject:songID]) {
        if (error) NSLog(@"sync: %@ failed: %@", path, error);
        _failed++;
    } else {
        self.filesDone++;
        _bytesFinished += size;
        [self scanSoon:NO];
    }
    if (_active.count == 0) [self finish];
    else [self notify];
}

- (void)URLSessionDidFinishEventsForBackgroundURLSession:(NSURLSession *)session {
    dispatch_async(dispatch_get_main_queue(), ^{
        void (^completion)(void) = self.backgroundCompletion;
        self.backgroundCompletion = nil;
        if (completion) completion();
    });
}

#pragma mark Helpers

- (void)saveManifest { [self writeJSON:_manifest to:self.manifestURL]; }

/// Deletes a file the server dropped, and any folders it leaves empty.
- (void)removeFile:(NSString *)path {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSURL *url = [FLLibrary.documents URLByAppendingPathComponent:path];
    [fm removeItemAtURL:url error:nil];
    NSString *root = FLLibrary.documents.URLByStandardizingPath.path;
    while (true) {
        url = url.URLByDeletingLastPathComponent;
        if (url.URLByStandardizingPath.path.length <= root.length) break;
        NSArray *left = [fm contentsOfDirectoryAtPath:url.path error:nil];
        if (!left || left.count) break;
        [fm removeItemAtURL:url error:nil];
    }
}

/// New songs join the library every ten seconds or so while downloading, not one by one.
- (void)scanSoon:(BOOL)force {
    if (_scanPending) return;
    double wait = force ? 1 : MAX(1, 10 - (CFAbsoluteTimeGetCurrent() - _lastScan));
    _scanPending = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(wait * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self->_scanPending = NO;
        self->_lastScan = CFAbsoluteTimeGetCurrent();
        [FLLibrary.shared scan];
    });
}

- (void)sample {
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    [_samples addObject:@[@(now), @(self.bytesDone)]];
    while (_samples.count > 2 && now - [_samples[0][0] doubleValue] > 3) [_samples removeObjectAtIndex:0];
    double span = now - [_samples[0][0] doubleValue];
    if (span > 0.5) self.speed = ([_samples.lastObject[1] doubleValue] - [_samples[0][1] doubleValue]) / span;
}

/// At most four times a second, which is what the progress on screen needs; the last change always gets out.
- (void)notify {
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (now - _lastNotice >= 0.25) {
        _lastNotice = now;
        [NSNotificationCenter.defaultCenter postNotificationName:FLSyncDidChange object:self];
        return;
    }
    if (_noticePending) return;
    _noticePending = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self->_noticePending = NO;
        self->_lastNotice = CFAbsoluteTimeGetCurrent();
        [NSNotificationCenter.defaultCenter postNotificationName:FLSyncDidChange object:self];
    });
}

/// What iOS 11 and later count as free for things the listener asked for; iOS 10 only knows the plain figure.
+ (long long)freeSpace {
    NSNumber *important = nil;
    [FLLibrary.documents getResourceValue:&important forKey:@"NSURLVolumeAvailableCapacityForImportantUsageKey" error:nil];
    if (important.longLongValue > 0) return important.longLongValue;
    return [[NSFileManager.defaultManager attributesOfFileSystemForPath:NSHomeDirectory() error:nil][NSFileSystemFreeSize] longLongValue];
}

+ (long long)capacity {
    return [[NSFileManager.defaultManager attributesOfFileSystemForPath:NSHomeDirectory() error:nil][NSFileSystemSize] longLongValue];
}

@end

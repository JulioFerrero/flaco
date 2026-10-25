#import "Flaco.h"
#import <CommonCrypto/CommonDigest.h>
#import <Security/Security.h>

@implementation FLSong

- (instancetype)initWithDictionary:(NSDictionary *)d {
    if ((self = [super init])) {
        _songID = d[@"id"] ?: @"";
        _path = d[@"path"] ?: @"";
        _size = [d[@"size"] longLongValue];
        _albumID = d[@"albumID"] ?: @"";
        _title = d[@"title"] ?: _path.lastPathComponent;
        _artist = d[@"artist"] ?: @"";
        _album = d[@"album"] ?: @"";
        _albumArtist = d[@"albumArtist"] ?: _artist;
        _year = [d[@"year"] integerValue];
        _coverArt = [d[@"coverArt"] isKindOfClass:NSString.class] ? d[@"coverArt"] : nil;
    }
    return self;
}

/// The keys the Swift Flaco wrote catalog.json with, so the 6s keeps its catalog across the change.
- (NSDictionary *)dictionary {
    NSMutableDictionary *d = [@{@"id": _songID, @"path": _path, @"size": @(_size), @"albumID": _albumID, @"title": _title,
                                @"artist": _artist, @"album": _album, @"albumArtist": _albumArtist, @"year": @(_year)} mutableCopy];
    if (_coverArt) d[@"coverArt"] = _coverArt;
    return d;
}

@end

@interface FLServer ()
@property (nonatomic, copy, nullable) NSString *password;
@end

@implementation FLServer {
    NSString *_cachedPassword;
}

+ (FLServer *)shared {
    static FLServer *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [FLServer new]; });
    return shared;
}

- (NSString *)address { return [NSUserDefaults.standardUserDefaults stringForKey:@"serverAddress"] ?: @""; }
- (NSString *)user { return [NSUserDefaults.standardUserDefaults stringForKey:@"serverUser"] ?: @""; }
- (NSString *)host { return [NSURL URLWithString:self.address].host ?: self.address; }
- (BOOL)configured { return self.address.length > 0 && self.password != nil; }

- (void)clearIfFreshInstall {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([defaults boolForKey:@"installed"]) return;
    [defaults setBool:YES forKey:@"installed"];
    self.password = nil;
    [defaults removeObjectForKey:@"serverAddress"];
    [defaults removeObjectForKey:@"serverUser"];
}

/// `music.example.com/` → `https://music.example.com`.
+ (NSString *)tidy:(NSString *)address {
    NSString *tidy = [address stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (tidy.length && [tidy rangeOfString:@"://"].location == NSNotFound) tidy = [@"https://" stringByAppendingString:tidy];
    while ([tidy hasSuffix:@"/"]) tidy = [tidy substringToIndex:tidy.length - 1];
    return tidy;
}

- (void)checkAddress:(NSString *)address user:(NSString *)user password:(NSString *)password completion:(void (^)(NSString *))completion {
    NSString *trimmed = [user stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    [self call:@"ping" items:@{} address:[FLServer tidy:address] user:trimmed password:password completion:^(NSDictionary *response, NSString *error) {
        completion(error);
    }];
}

- (void)saveAddress:(NSString *)address user:(NSString *)user password:(NSString *)password {
    NSString *tidy = [FLServer tidy:address];
    if (self.address.length && ![tidy isEqualToString:self.address]) [FLSync.shared forgetServer];
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setObject:tidy forKey:@"serverAddress"];
    [defaults setObject:[user stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet] forKey:@"serverUser"];
    self.password = password;
}

- (void)disconnect {
    self.password = nil;
    [NSUserDefaults.standardUserDefaults removeObjectForKey:@"serverAddress"];
    [NSUserDefaults.standardUserDefaults removeObjectForKey:@"serverUser"];
    [FLSync.shared forgetServer];
}

#pragma mark Requests

- (void)listing:(void (^)(NSArray<FLSong *> *, BOOL, NSString *))completion {
    [self call:@"getScanStatus" items:@{} completion:^(NSDictionary *status, NSString *ignored) {
        BOOL scanning = [status[@"scanStatus"][@"scanning"] boolValue];
        [self songsAfter:[NSMutableArray array] scanning:scanning completion:completion];
    }];
}

/// Every song, 500 at a time.
- (void)songsAfter:(NSMutableArray<NSDictionary *> *)raw scanning:(BOOL)scanning
        completion:(void (^)(NSArray<FLSong *> *, BOOL, NSString *))completion {
    NSDictionary *items = @{@"query": @"", @"artistCount": @"0", @"albumCount": @"0", @"songCount": @"500",
                            @"songOffset": [NSString stringWithFormat:@"%lu", (unsigned long)raw.count]};
    [self call:@"search3" items:items completion:^(NSDictionary *response, NSString *error) {
        if (error) {
            completion(nil, NO, error);
            return;
        }
        NSArray *songs = response[@"searchResult3"][@"song"];
        if (![songs isKindOfClass:NSArray.class]) songs = @[];
        [raw addObjectsFromArray:songs];
        if (songs.count == 500) [self songsAfter:raw scanning:scanning completion:completion];
        else completion([FLServer songsFrom:raw], scanning, nil);
    }];
}

+ (NSArray<FLSong *> *)songsFrom:(NSArray<NSDictionary *> *)raw {
    NSMutableArray *songs = [NSMutableArray array];
    NSMutableSet *taken = [NSMutableSet set];
    for (NSDictionary *item in raw) {
        NSString *songID = item[@"id"], *reported = item[@"path"];
        if (![songID isKindOfClass:NSString.class] || ![reported isKindOfClass:NSString.class]) continue;
        NSString *path = [self localPath:reported keepingSource:NO];
        // The same album sent in two ways keeps both copies apart.
        if ([taken containsObject:path.lowercaseString]) path = [self localPath:reported keepingSource:YES];
        [taken addObject:path.lowercaseString];
        NSString *artist = [item[@"artist"] isKindOfClass:NSString.class] ? item[@"artist"] : @"";
        NSString *albumArtist = [item[@"displayAlbumArtist"] isKindOfClass:NSString.class] ? item[@"displayAlbumArtist"] : artist;
        [songs addObject:[[FLSong alloc] initWithDictionary:@{
            @"id": songID, @"path": path, @"size": item[@"size"] ?: @0, @"albumID": item[@"albumId"] ?: @"",
            @"title": item[@"title"] ?: path.lastPathComponent, @"artist": artist, @"album": item[@"album"] ?: @"",
            @"albumArtist": albumArtist, @"year": item[@"year"] ?: @0, @"coverArt": item[@"coverArt"] ?: [NSNull null],
        }]];
    }
    return songs;
}

/// Navidrome reports where it keeps a file: its library folder, then the way the music came in (the Finder
/// share's Uploads, Syncthing's Mac), then the music's own folders. Only that last part is kept.
+ (NSString *)localPath:(NSString *)reported keepingSource:(BOOL)keepingSource {
    NSMutableArray *parts = [NSMutableArray array];
    for (NSString *part in [reported componentsSeparatedByString:@"/"]) {
        if (part.length && ![part isEqualToString:@"."] && ![part isEqualToString:@".."]) [parts addObject:part];
    }
    if ([reported hasPrefix:@"/"] && parts.count > 2) [parts removeObjectsInRange:NSMakeRange(0, keepingSource ? 1 : 2)];
    return [parts componentsJoinedByString:@"/"];
}

- (NSURL *)downloadURL:(NSString *)songID {
    return [self urlFor:@"download" items:@{@"id": songID} address:self.address user:self.user password:self.password];
}

- (NSURL *)coverURL:(NSString *)coverID size:(NSInteger)size {
    return [self urlFor:@"getCoverArt" items:@{@"id": coverID, @"size": [NSString stringWithFormat:@"%ld", (long)size]}
                address:self.address user:self.user password:self.password];
}

- (void)call:(NSString *)endpoint items:(NSDictionary *)items completion:(void (^)(NSDictionary *, NSString *))completion {
    [self call:endpoint items:items address:self.address user:self.user password:self.password completion:completion];
}

- (void)call:(NSString *)endpoint items:(NSDictionary *)items address:(NSString *)address user:(NSString *)user
    password:(NSString *)password completion:(void (^)(NSDictionary *, NSString *))completion {
    NSString *host = [NSURL URLWithString:address].host ?: @"the server";
    NSURL *url = password ? [self urlFor:endpoint items:items address:address user:user password:password] : nil;
    if (!url) {
        completion(nil, @"No server set up.");
        return;
    }
    NSURLRequest *request = [NSURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:30];
    [[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSString *failure = nil;
        NSDictionary *body = nil;
        if (error || !data) {
            failure = [NSString stringWithFormat:@"Can't reach %@.", host];
        } else {
            id root = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            body = [root isKindOfClass:NSDictionary.class] ? root[@"subsonic-response"] : nil;
            if (![body isKindOfClass:NSDictionary.class]) {
                failure = [NSString stringWithFormat:@"%@ isn't a Subsonic server.", host];
                body = nil;
            } else if (![body[@"status"] isEqual:@"ok"]) {
                NSDictionary *problem = body[@"error"];
                failure = [problem[@"code"] integerValue] == 40 ? @"Wrong user or password." : problem[@"message"] ?: @"The server refused.";
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(failure ? nil : body, failure); });
    }] resume];
}

/// Token sign-in: the password never travels, only a hash of it with a fresh salt.
- (NSURL *)urlFor:(NSString *)endpoint items:(NSDictionary *)items address:(NSString *)address user:(NSString *)user password:(NSString *)password {
    NSURLComponents *components = [NSURLComponents componentsWithString:address];
    if (!components.host || !password) return nil;
    NSString *salt = [[NSUUID.UUID.UUIDString stringByReplacingOccurrencesOfString:@"-" withString:@""] substringToIndex:12].lowercaseString;
    NSData *input = [[password stringByAppendingString:salt] dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_MD5_DIGEST_LENGTH];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    CC_MD5(input.bytes, (CC_LONG)input.length, digest);
#pragma clang diagnostic pop
    NSMutableString *token = [NSMutableString string];
    for (int i = 0; i < CC_MD5_DIGEST_LENGTH; i++) [token appendFormat:@"%02x", digest[i]];
    components.path = [(components.path ?: @"") stringByAppendingFormat:@"/rest/%@", endpoint];
    NSMutableArray *query = [NSMutableArray arrayWithArray:@[
        [NSURLQueryItem queryItemWithName:@"u" value:user], [NSURLQueryItem queryItemWithName:@"t" value:token],
        [NSURLQueryItem queryItemWithName:@"s" value:salt], [NSURLQueryItem queryItemWithName:@"v" value:@"1.16.1"],
        [NSURLQueryItem queryItemWithName:@"c" value:@"Flaco"], [NSURLQueryItem queryItemWithName:@"f" value:@"json"],
    ]];
    [items enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
        [query addObject:[NSURLQueryItem queryItemWithName:key value:value]];
    }];
    components.queryItems = query;
    return components.URL;
}

#pragma mark Keychain

- (NSDictionary *)keychainQuery {
    return @{(id)kSecClass: (id)kSecClassGenericPassword, (id)kSecAttrService: @"flaco.server", (id)kSecAttrAccount: @"password"};
}

- (NSString *)password {
    if (_cachedPassword) return _cachedPassword;
    NSMutableDictionary *query = [self.keychainQuery mutableCopy];
    query[(id)kSecReturnData] = @YES;
    query[(id)kSecMatchLimit] = (id)kSecMatchLimitOne;
    CFTypeRef item = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)query, &item) != errSecSuccess || !item) return nil;
    NSData *data = (__bridge_transfer NSData *)item;
    _cachedPassword = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return _cachedPassword;
}

- (void)setPassword:(NSString *)password {
    SecItemDelete((__bridge CFDictionaryRef)self.keychainQuery);
    _cachedPassword = password;
    if (!password) return;
    NSMutableDictionary *item = [self.keychainQuery mutableCopy];
    item[(id)kSecValueData] = [password dataUsingEncoding:NSUTF8StringEncoding];
    // Background downloads may need it while the phone is locked.
    item[(id)kSecAttrAccessible] = (id)kSecAttrAccessibleAfterFirstUnlock;
    SecItemAdd((__bridge CFDictionaryRef)item, NULL);
}

@end

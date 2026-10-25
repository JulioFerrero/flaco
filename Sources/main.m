#import "Flaco.h"

@interface FLAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation FLAppDelegate {
    NSTimer *_rescan;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    [FLServer.shared clearIfFreshInstall];
    [self dropSwiftCaches];
    [FLLibrary.shared load];
    [FLPlayer.shared restore];
    [FLSync.shared reconnect];
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [FLMainViewController new];
    [self.window makeKeyAndVisible];
    return YES;
}

/// Finder copies into Documents while Flaco is open, so it looks again every few seconds while it's on screen.
- (void)applicationDidBecomeActive:(UIApplication *)application {
    [FLLibrary.shared scan];
    [FLSync.shared startIfDue];
    [_rescan invalidate];
    _rescan = [NSTimer scheduledTimerWithTimeInterval:8 target:FLLibrary.shared selector:@selector(scan) userInfo:nil repeats:YES];
}

- (void)applicationWillResignActive:(UIApplication *)application {
    [_rescan invalidate];
    _rescan = nil;
    [FLPlayer.shared save];
}

- (void)applicationWillTerminate:(UIApplication *)application {
    [FLPlayer.shared save];
}

/// iOS wakes Flaco when background downloads finish; the session reconnects when FLSync starts.
- (void)application:(UIApplication *)application handleEventsForBackgroundURLSession:(NSString *)identifier completionHandler:(void (^)(void))completion {
    FLSync.shared.backgroundCompletion = completion;
}

/// The Swift Flaco's index, covers and waveforms, which this one makes again in its own form. Its list of
/// downloaded files and the server's catalog stay: they're read as they are.
- (void)dropSwiftCaches {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([defaults boolForKey:@"droppedSwiftCaches"]) return;
    [defaults setBool:YES forKey:@"droppedSwiftCaches"];
    NSFileManager *fm = NSFileManager.defaultManager;
    NSURL *support = [[fm URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject URLByAppendingPathComponent:@"Flaco"];
    NSURL *caches = [fm URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject;
    for (NSURL *url in @[[support URLByAppendingPathComponent:@"library.json"], [support URLByAppendingPathComponent:@"palettes.json"],
                         [support URLByAppendingPathComponent:@"Covers"], [support URLByAppendingPathComponent:@"Waveforms"],
                         [caches URLByAppendingPathComponent:@"Waveforms"]]) {
        [fm removeItemAtURL:url error:nil];
    }
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(FLAppDelegate.class));
    }
}

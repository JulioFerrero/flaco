#import "Lite.h"

@interface FLAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation FLAppDelegate {
    NSTimer *_rescan;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    [FLLibrary.shared load];
    [FLPlayer.shared restore];
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [FLMainViewController new];
    [self.window makeKeyAndVisible];
    return YES;
}

/// Finder copies into Documents while Flaco Lite is open, so it looks again every few seconds while it's on screen.
- (void)applicationDidBecomeActive:(UIApplication *)application {
    [FLLibrary.shared scan];
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

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(FLAppDelegate.class));
    }
}

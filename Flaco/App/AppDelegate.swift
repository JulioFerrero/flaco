import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        Library.shared.load()
        Player.shared.restore()

        let navigation = UINavigationController(rootViewController: MainViewController())
        navigation.setNavigationBarHidden(true, animated: false)
        // Keeps the edge swipe back working with the bar hidden.
        navigation.interactivePopGestureRecognizer?.delegate = nil

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        self.window = window
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        Library.shared.scan()
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        Player.shared.save()
    }

    func applicationWillTerminate(_ application: UIApplication) {
        Player.shared.save()
    }

    /// "Open in Flaco" from another app.
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        Library.shared.importFiles([url])
        return true
    }
}

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
        Server.shared.adoptSeed()
        Sync.shared.reconnect()
        if application.applicationState == .background { setVisible(false) }

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
        setVisible(true)
        Library.shared.scan()
        Sync.shared.startIfDue()
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        setVisible(false)
        Player.shared.save()
    }

    /// Work only the screen needs stops while Flaco is out of sight.
    private func setVisible(_ visible: Bool) {
        Waveforms.shared.setPaused(!visible)
        Player.shared.analyzesSpectrum = visible
    }

    /// Downloads finished while Flaco was closed; it was woken to place them.
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        Sync.shared.backgroundCompletion = completionHandler
        Sync.shared.reconnect()
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

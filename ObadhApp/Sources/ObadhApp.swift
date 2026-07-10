import SwiftUI
import UIKit

@main
enum ObadhMain {
    static func main() {
        UIApplicationMain(
            CommandLine.argc,
            CommandLine.unsafeArgv,
            NSStringFromClass(ObadhApplication.self),
            NSStringFromClass(ObadhAppDelegate.self)
        )
    }
}

final class ObadhApplication: UIApplication {
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {}

    override func pressesChanged(_ presses: Set<UIPress>, with event: UIPressesEvent?) {}

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {}

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {}

    override var keyCommands: [UIKeyCommand]? {
        []
    }
}

final class ObadhAppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: "Default Configuration",
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = ObadhSceneDelegate.self
        return configuration
    }
}

final class ObadhSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = makeRootViewController()
        window.makeKeyAndVisible()
        self.window = window
    }

    private func makeRootViewController() -> UIViewController {
        // Measurement and test harnesses reachable only by launch argument, and only
        // in Debug. Release has no text input anywhere in the app.
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--keyboard-geometry-probe")
            || arguments.contains("--native-keyboard-geometry-probe") {
            return KeyboardGeometryProbeViewController()
        }

        if arguments.contains("--keyboard-test") {
            return UINavigationController(rootViewController: KeyboardTestViewController())
        }
        #endif

        return UIHostingController(rootView: RootView())
    }
}

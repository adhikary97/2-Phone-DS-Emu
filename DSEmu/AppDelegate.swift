import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        _ = EmulatorCore.shared.initialize()
        return true
    }

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        switch connectingSceneSession.role {
        case .windowExternalDisplayNonInteractive:
            return UISceneConfiguration(name: "External Display",
                                        sessionRole: .windowExternalDisplayNonInteractive)
        default:
            return UISceneConfiguration(name: "Phone Display",
                                        sessionRole: .windowApplication)
        }
    }

    func application(_ application: UIApplication,
                     didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
    }
}

import UIKit

class ExternalDisplaySceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let topScreenVC = TopScreenViewController()
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = topScreenVC
        window.makeKeyAndVisible()
        self.window = window

        // Register the external display renderer with the emulator core
        EmulatorCore.shared.externalRenderer = topScreenVC.screenView.renderer
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        EmulatorCore.shared.externalRenderer = nil
    }
}

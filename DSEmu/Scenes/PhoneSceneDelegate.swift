import UIKit

class PhoneSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)
        let configuration = TwoPhoneConfiguration.current
        if shouldShowSetup(for: configuration) {
            window.rootViewController = TwoPhoneSetupViewController { [weak self] _ in
                self?.showConfiguredRoot(animated: true)
            }
        } else {
            window.rootViewController = configuredRootViewController()
        }
        window.makeKeyAndVisible()
        self.window = window
    }

    private func shouldShowSetup(for configuration: TwoPhoneConfiguration) -> Bool {
        guard !configuration.requiresOnDeviceSetup else { return true }
        guard let romURL = configuration.autoloadROMURL() else { return true }
        return !FileManager.default.fileExists(atPath: romURL.path)
    }

    private func configuredRootViewController() -> UIViewController {
        TwoPhoneConfiguration.current.role == .display
            ? TopScreenViewController()
            : BottomScreenViewController()
    }

    private func showConfiguredRoot(animated: Bool) {
        guard let window else { return }
        let change = { window.rootViewController = self.configuredRootViewController() }
        if animated {
            UIView.transition(
                with: window,
                duration: 0.35,
                options: [.transitionCrossDissolve, .allowAnimatedContent],
                animations: change
            )
        } else {
            change()
        }
    }
}

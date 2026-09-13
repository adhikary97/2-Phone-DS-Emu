import UIKit

class TopScreenViewController: UIViewController {

    let screenView = DSScreenView()
    private var didAttemptAutoload = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        screenView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(screenView)

        // Fill the external display, maintaining 4:3 aspect ratio (letterboxed)
        NSLayoutConstraint.activate([
            screenView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            screenView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            screenView.topAnchor.constraint(equalTo: view.topAnchor),
            screenView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        installTwoPhoneStatusLabelIfNeeded()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // Configure for external screen if available
        if let windowScene = view.window?.windowScene,
           let screen = windowScene.screen as UIScreen? {
            screenView.configureForExternalDisplay(screen: screen)
            EmulatorCore.shared.externalRenderer = screenView.renderer
        }

        guard !didAttemptAutoload, let url = TwoPhoneConfiguration.current.autoloadROMURL() else { return }
        didAttemptAutoload = true
        if !EmulatorCore.shared.loadROM(at: url) {
            print("TWO_PHONE_ROM_LOAD_FAILED \(url.path)")
        }
    }

    override var prefersStatusBarHidden: Bool { true }
}

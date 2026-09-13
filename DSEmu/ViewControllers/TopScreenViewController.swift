import UIKit

class TopScreenViewController: UIViewController {

    private enum Palette {
        static let shell = UIColor(red: 0.090, green: 0.098, blue: 0.118, alpha: 1)
        static let frameEdge = UIColor.white.withAlphaComponent(0.16)
        static let speaker = UIColor(red: 0.025, green: 0.029, blue: 0.036, alpha: 0.9)
    }

    let screenView = DSScreenView()
    private let screenFrame = UIView()
    private let leftSpeaker = UIStackView()
    private let rightSpeaker = UIStackView()
    private var didAttemptAutoload = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.shell

        screenView.translatesAutoresizingMaskIntoConstraints = false
        screenView.layer.cornerRadius = 12
        screenView.layer.cornerCurve = .continuous
        screenView.layer.masksToBounds = true
        view.addSubview(screenView)

        configureScreenFrame()
        configureSpeaker(leftSpeaker, identifier: "top-display.speaker.left")
        configureSpeaker(rightSpeaker, identifier: "top-display.speaker.right")
        view.addSubview(screenFrame)
        view.addSubview(leftSpeaker)
        view.addSubview(rightSpeaker)

        // Use the largest centered DS-sized rectangle that fits this phone.
        // Making the view itself 4:3 prevents stretching and avoids allocating
        // drawable space to letterbox bars.
        let useAllWidth = screenView.widthAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.widthAnchor
        )
        useAllWidth.priority = UILayoutPriority(999)
        let useAllHeight = screenView.heightAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.heightAnchor
        )
        useAllHeight.priority = UILayoutPriority(998)

        NSLayoutConstraint.activate([
            screenView.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            screenView.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            screenView.widthAnchor.constraint(equalTo: screenView.heightAnchor, multiplier: 256.0 / 192.0),
            screenView.widthAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.widthAnchor),
            screenView.heightAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.heightAnchor),
            useAllWidth,
            useAllHeight,

            screenFrame.topAnchor.constraint(equalTo: screenView.topAnchor),
            screenFrame.leadingAnchor.constraint(equalTo: screenView.leadingAnchor),
            screenFrame.trailingAnchor.constraint(equalTo: screenView.trailingAnchor),
            screenFrame.bottomAnchor.constraint(equalTo: screenView.bottomAnchor),

            leftSpeaker.trailingAnchor.constraint(equalTo: screenView.leadingAnchor, constant: -16),
            leftSpeaker.centerYAnchor.constraint(equalTo: screenView.centerYAnchor),
            rightSpeaker.leadingAnchor.constraint(equalTo: screenView.trailingAnchor, constant: 16),
            rightSpeaker.centerYAnchor.constraint(equalTo: screenView.centerYAnchor),
        ])
        installTwoPhoneStatusLabelIfNeeded()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let isLandscape = view.bounds.width > view.bounds.height
        leftSpeaker.isHidden = !isLandscape
        rightSpeaker.isHidden = !isLandscape
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

    private func configureScreenFrame() {
        screenFrame.translatesAutoresizingMaskIntoConstraints = false
        screenFrame.accessibilityIdentifier = "top-display.frame"
        screenFrame.isUserInteractionEnabled = false
        screenFrame.accessibilityElementsHidden = true
        screenFrame.backgroundColor = .clear
        screenFrame.layer.cornerRadius = 12
        screenFrame.layer.cornerCurve = .continuous
        screenFrame.layer.borderWidth = 4
        screenFrame.layer.borderColor = Palette.frameEdge.cgColor
    }

    private func configureSpeaker(_ speaker: UIStackView, identifier: String) {
        speaker.translatesAutoresizingMaskIntoConstraints = false
        speaker.accessibilityIdentifier = identifier
        speaker.isUserInteractionEnabled = false
        speaker.accessibilityElementsHidden = true
        speaker.axis = .vertical
        speaker.alignment = .center
        speaker.spacing = 7

        for _ in 0..<5 {
            let slot = UIView()
            slot.translatesAutoresizingMaskIntoConstraints = false
            slot.backgroundColor = Palette.speaker
            slot.layer.cornerRadius = 1.5
            speaker.addArrangedSubview(slot)
            NSLayoutConstraint.activate([
                slot.widthAnchor.constraint(equalToConstant: 14),
                slot.heightAnchor.constraint(equalToConstant: 3),
            ])
        }
    }
}

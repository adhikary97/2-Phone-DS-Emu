import UIKit

final class TwoPhoneSetupViewController: UIViewController {
    private enum Palette {
        static let graphite = UIColor(red: 0.071, green: 0.078, blue: 0.090, alpha: 1)
        static let warmPanel = UIColor(red: 0.925, green: 0.914, blue: 0.882, alpha: 1)
        static let mutedText = UIColor(red: 0.65, green: 0.67, blue: 0.70, alpha: 1)
        static let controllerBlue = UIColor(red: 0.290, green: 0.490, blue: 1.0, alpha: 1)
        static let displayRed = UIColor(red: 0.906, green: 0.357, blue: 0.333, alpha: 1)
        static let successGreen = UIColor(red: 0.322, green: 0.769, blue: 0.541, alpha: 1)
    }

    private let onComplete: (TwoPhoneRole) -> Void
    private let romButton = UIButton(type: .system)
    private let controllerButton = UIButton(type: .system)
    private let displayButton = UIButton(type: .system)
    private var selectedROMURL: URL?

    init(onComplete: @escaping (TwoPhoneRole) -> Void) {
        self.onComplete = onComplete
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.graphite
        selectedROMURL = TwoPhonePreferences.shared.bestAvailableROMURL()
        buildInterface()
        updateROMSelection()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .allButUpsideDown }

    private func buildInterface() {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)

        let content = UIStackView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.axis = .vertical
        content.spacing = 18
        content.alignment = .fill
        scrollView.addSubview(content)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 24),
            content.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 24),
            content.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -24),
            content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
        ])

        let brand = makeLabel("▯  ▯   TWO-PHONE DS", size: 12, weight: .bold, color: Palette.successGreen)
        brand.accessibilityLabel = "Two-Phone DS"
        content.addArrangedSubview(brand)

        let title = makeLabel("Set up this phone", size: 34, weight: .bold, color: .white)
        title.adjustsFontSizeToFitWidth = true
        title.minimumScaleFactor = 0.8
        content.addArrangedSubview(title)

        let subtitle = makeLabel(
            "Pick the same game on both phones, then give each phone a different job.",
            size: 16,
            weight: .regular,
            color: Palette.mutedText
        )
        subtitle.numberOfLines = 0
        content.addArrangedSubview(subtitle)
        content.setCustomSpacing(28, after: subtitle)

        let gameHeading = makeLabel("GAME", size: 12, weight: .bold, color: Palette.mutedText)
        content.addArrangedSubview(gameHeading)

        romButton.accessibilityIdentifier = "twoPhone.romPicker"
        romButton.addTarget(self, action: #selector(chooseROM), for: .touchUpInside)
        romButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 68).isActive = true
        content.addArrangedSubview(romButton)
        content.setCustomSpacing(28, after: romButton)

        let roleHeading = makeLabel("THIS PHONE WILL BE THE…", size: 12, weight: .bold, color: Palette.mutedText)
        content.addArrangedSubview(roleHeading)

        configureRoleButton(
            controllerButton,
            identifier: "twoPhone.controllerRole",
            title: "Controller",
            subtitle: "Bottom screen + controls",
            imageName: "gamecontroller.fill",
            color: Palette.controllerBlue,
            action: #selector(selectController)
        )
        configureRoleButton(
            displayButton,
            identifier: "twoPhone.displayRole",
            title: "Top Display",
            subtitle: "Top screen only",
            imageName: "rectangle.inset.filled",
            color: Palette.displayRed,
            action: #selector(selectDisplay)
        )

        let roles = UIStackView(arrangedSubviews: [controllerButton, displayButton])
        roles.axis = .horizontal
        roles.distribution = .fillEqually
        roles.spacing = 12
        roles.heightAnchor.constraint(greaterThanOrEqualToConstant: 132).isActive = true
        content.addArrangedSubview(roles)

        let footer = makeLabel(
            "Keep both phones nearby with Wi-Fi enabled. They will find each other and start automatically — no Mac or IP address needed.",
            size: 13,
            weight: .medium,
            color: Palette.mutedText
        )
        footer.numberOfLines = 0
        footer.textAlignment = .center
        content.addArrangedSubview(footer)
    }

    private func makeLabel(
        _ text: String,
        size: CGFloat,
        weight: UIFont.Weight,
        color: UIColor
    ) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        return label
    }

    private func configureRoleButton(
        _ button: UIButton,
        identifier: String,
        title: String,
        subtitle: String,
        imageName: String,
        color: UIColor,
        action: Selector
    ) {
        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.subtitle = subtitle
        configuration.image = UIImage(systemName: imageName)
        configuration.imagePlacement = .top
        configuration.imagePadding = 12
        configuration.titlePadding = 6
        configuration.cornerStyle = .large
        configuration.baseBackgroundColor = color
        configuration.baseForegroundColor = .white
        configuration.titleAlignment = .center
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var updated = attributes
            updated.font = .systemFont(ofSize: 18, weight: .bold)
            return updated
        }
        configuration.subtitleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var updated = attributes
            updated.font = .systemFont(ofSize: 12, weight: .medium)
            return updated
        }
        button.configuration = configuration
        button.accessibilityIdentifier = identifier
        button.accessibilityLabel = "\(title), \(subtitle)"
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    private func updateROMSelection() {
        var configuration = UIButton.Configuration.filled()
        configuration.cornerStyle = .large
        configuration.baseBackgroundColor = Palette.warmPanel
        configuration.baseForegroundColor = Palette.graphite
        configuration.imagePlacement = .leading
        configuration.imagePadding = 14
        configuration.titleAlignment = .leading

        if let selectedROMURL {
            configuration.title = selectedROMURL.deletingPathExtension().lastPathComponent
            configuration.subtitle = "Selected — tap to choose a different ROM"
            configuration.image = UIImage(systemName: "checkmark.circle.fill")
            configuration.baseForegroundColor = Palette.graphite
            romButton.accessibilityLabel = "Selected ROM, \(selectedROMURL.lastPathComponent). Tap to change."
        } else {
            configuration.title = "Choose a Nintendo DS ROM"
            configuration.subtitle = "Select the same .nds file on both phones"
            configuration.image = UIImage(systemName: "doc.badge.plus")
            romButton.accessibilityLabel = "Choose a Nintendo DS ROM"
        }

        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var updated = attributes
            updated.font = .systemFont(ofSize: 16, weight: .bold)
            return updated
        }
        configuration.subtitleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var updated = attributes
            updated.font = .systemFont(ofSize: 12, weight: .regular)
            return updated
        }
        romButton.configuration = configuration

        let hasROM = selectedROMURL != nil
        controllerButton.isEnabled = hasROM
        displayButton.isEnabled = hasROM
        controllerButton.alpha = hasROM ? 1 : 0.42
        displayButton.alpha = hasROM ? 1 : 0.42
    }

    @objc private func chooseROM() {
        present(ROMPicker.make(delegate: self), animated: true)
    }

    @objc private func selectController() {
        completeSetup(role: .controller)
    }

    @objc private func selectDisplay() {
        completeSetup(role: .display)
    }

    private func completeSetup(role: TwoPhoneRole) {
        guard let selectedROMURL else { return }
        TwoPhonePreferences.shared.save(role: role, romName: selectedROMURL.lastPathComponent)
        TwoPhoneConfiguration.reloadFromProcessInfo()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onComplete(role)
    }

    private func showImportError(_ error: Error) {
        let alert = UIAlertController(
            title: "Couldn’t import ROM",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

extension TwoPhoneSetupViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let sourceURL = urls.first else { return }
        guard sourceURL.pathExtension.lowercased() == "nds" else {
            showImportError(NSError(
                domain: "TwoPhoneSetup",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Choose a file ending in .nds."]
            ))
            return
        }

        let hasSecurityAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityAccess { sourceURL.stopAccessingSecurityScopedResource() }
        }

        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let destinationURL = documents.appendingPathComponent(sourceURL.lastPathComponent)

        do {
            if sourceURL.standardizedFileURL != destinationURL.standardizedFileURL {
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            }
            selectedROMURL = destinationURL
            RecentROMs.shared.add(ROMEntry(
                name: destinationURL.deletingPathExtension().lastPathComponent,
                path: destinationURL.lastPathComponent
            ))
            updateROMSelection()
        } catch {
            showImportError(error)
        }
    }
}

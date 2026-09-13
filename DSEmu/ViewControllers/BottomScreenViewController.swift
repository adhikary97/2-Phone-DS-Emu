import UIKit

class BottomScreenViewController: UIViewController {

    private enum Palette {
        static let shell = UIColor(red: 0.090, green: 0.098, blue: 0.118, alpha: 1)
        static let bezel = UIColor(red: 0.027, green: 0.031, blue: 0.039, alpha: 1)
        static let bezelEdge = UIColor.white.withAlphaComponent(0.12)
    }

    let screenView = DSScreenView()
    private let screenBezel = UIView()
    private var hasROMLoaded = false
    private var didAttemptAutoload = false

    // MARK: - Load ROM prompt

    private let loadROMContainer = UIView()
    private var recentsTableView: UITableView!
    private var recents: [ROMEntry] = []

    // MARK: - Emulator layout constraints (swapped on rotation)

    private var portraitConstraints: [NSLayoutConstraint] = []
    private var landscapeConstraints: [NSLayoutConstraint] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.shell

        screenBezel.translatesAutoresizingMaskIntoConstraints = false
        screenBezel.backgroundColor = Palette.bezel
        screenBezel.layer.cornerRadius = 20
        screenBezel.layer.cornerCurve = .continuous
        screenBezel.layer.borderWidth = 1
        screenBezel.layer.borderColor = Palette.bezelEdge.cgColor
        screenBezel.layer.shadowColor = UIColor.black.cgColor
        screenBezel.layer.shadowOpacity = 0.45
        screenBezel.layer.shadowRadius = 16
        screenBezel.layer.shadowOffset = CGSize(width: 0, height: 8)
        screenBezel.isHidden = true
        view.addSubview(screenBezel)

        screenView.translatesAutoresizingMaskIntoConstraints = false
        screenView.layer.cornerRadius = 7
        screenView.layer.cornerCurve = .continuous
        screenView.layer.masksToBounds = true
        screenBezel.addSubview(screenView)

        NSLayoutConstraint.activate([
            screenView.topAnchor.constraint(equalTo: screenBezel.topAnchor, constant: 8),
            screenView.leadingAnchor.constraint(equalTo: screenBezel.leadingAnchor, constant: 8),
            screenView.trailingAnchor.constraint(equalTo: screenBezel.trailingAnchor, constant: -8),
            screenView.bottomAnchor.constraint(equalTo: screenBezel.bottomAnchor, constant: -8),
            screenView.widthAnchor.constraint(equalTo: screenView.heightAnchor, multiplier: 256.0 / 192.0),
        ])

        EmulatorCore.shared.phoneRenderer = screenView.renderer

        setupOnScreenControls()
        setupLoadROMPrompt()
        buildLayoutConstraints()
        applyLayoutForCurrentOrientation()

        onScreenControls?.isHidden = true
        installTwoPhoneStatusLabelIfNeeded()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didAttemptAutoload, let url = TwoPhoneConfiguration.current.autoloadROMURL() else { return }
        didAttemptAutoload = true
        launchROM(at: url)
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .allButUpsideDown
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate { _ in
            self.applyLayoutForSize(size)
        }
    }

    // MARK: - Layout

    private func buildLayoutConstraints() {
        guard let controls = onScreenControls else { return }

        // Portrait: the touch screen sits in a recessed bezel above a separate
        // control deck.
        portraitConstraints = [
            screenBezel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 56),
            screenBezel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            screenBezel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),

            controls.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controls.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controls.topAnchor.constraint(equalTo: screenBezel.bottomAnchor, constant: 10),
            controls.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ]

        let preferredLandscapeWidth = screenBezel.widthAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.widthAnchor,
            constant: -300
        )
        preferredLandscapeWidth.priority = .defaultHigh
        let preferredLandscapeHeight = screenBezel.heightAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.heightAnchor,
            constant: -62
        )
        preferredLandscapeHeight.priority = UILayoutPriority(749)

        // Landscape: the screen scales inside a protected center lane. The
        // 150-point side lanes belong exclusively to the control wings. With
        // Select and Start in those wings, the center can reclaim its bottom.
        landscapeConstraints = [
            screenBezel.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            screenBezel.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor, constant: 21),
            screenBezel.leadingAnchor.constraint(
                greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor,
                constant: 150
            ),
            screenBezel.trailingAnchor.constraint(
                lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor,
                constant: -150
            ),
            screenBezel.topAnchor.constraint(
                greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor,
                constant: 52
            ),
            screenBezel.bottomAnchor.constraint(
                lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -10
            ),
            preferredLandscapeWidth,
            preferredLandscapeHeight,

            controls.topAnchor.constraint(equalTo: view.topAnchor),
            controls.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            controls.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controls.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ]
    }

    private func applyLayoutForCurrentOrientation() {
        applyLayoutForSize(view.bounds.size)
    }

    private func applyLayoutForSize(_ size: CGSize) {
        let isLandscape = size.width > size.height
        NSLayoutConstraint.deactivate(portraitConstraints)
        NSLayoutConstraint.deactivate(landscapeConstraints)
        NSLayoutConstraint.activate(isLandscape ? landscapeConstraints : portraitConstraints)
        onScreenControls?.setLandscape(isLandscape)
    }

    // MARK: - Load ROM Prompt

    private func setupLoadROMPrompt() {
        loadROMContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(loadROMContainer)

        NSLayoutConstraint.activate([
            loadROMContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 40),
            loadROMContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 30),
            loadROMContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -30),
            loadROMContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
        ])

        let titleLabel = UILabel()
        titleLabel.text = "DSEmu"
        titleLabel.font = .systemFont(ofSize: 32, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let subtitleLabel = UILabel()
        subtitleLabel.text = "Nintendo DS Emulator"
        subtitleLabel.font = .systemFont(ofSize: 15, weight: .regular)
        subtitleLabel.textColor = .lightGray
        subtitleLabel.textAlignment = .center
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        let loadButton = UIButton(type: .system)
        loadButton.translatesAutoresizingMaskIntoConstraints = false
        loadButton.setTitle("  Load ROM (.nds)", for: .normal)
        loadButton.setImage(UIImage(systemName: "folder.badge.plus"), for: .normal)
        loadButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        loadButton.tintColor = .white
        loadButton.setTitleColor(.white, for: .normal)
        loadButton.backgroundColor = UIColor(red: 0.2, green: 0.5, blue: 1.0, alpha: 1.0)
        loadButton.layer.cornerRadius = 14
        loadButton.addTarget(self, action: #selector(loadROMTapped), for: .touchUpInside)

        // Recents table
        let recentsLabel = UILabel()
        recentsLabel.text = "Recent Games"
        recentsLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        recentsLabel.textColor = .white
        recentsLabel.translatesAutoresizingMaskIntoConstraints = false

        recentsTableView = UITableView(frame: .zero, style: .plain)
        recentsTableView.translatesAutoresizingMaskIntoConstraints = false
        recentsTableView.backgroundColor = .clear
        recentsTableView.separatorColor = UIColor.white.withAlphaComponent(0.15)
        recentsTableView.dataSource = self
        recentsTableView.delegate = self
        recentsTableView.register(UITableViewCell.self, forCellReuseIdentifier: "rom")

        loadROMContainer.addSubview(titleLabel)
        loadROMContainer.addSubview(subtitleLabel)
        loadROMContainer.addSubview(loadButton)
        loadROMContainer.addSubview(recentsLabel)
        loadROMContainer.addSubview(recentsTableView)

        recents = RecentROMs.shared.entries
        let showRecents = !recents.isEmpty

        recentsLabel.isHidden = !showRecents
        recentsTableView.isHidden = !showRecents

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: loadROMContainer.topAnchor),
            titleLabel.centerXAnchor.constraint(equalTo: loadROMContainer.centerXAnchor),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.centerXAnchor.constraint(equalTo: loadROMContainer.centerXAnchor),

            loadButton.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 30),
            loadButton.leadingAnchor.constraint(equalTo: loadROMContainer.leadingAnchor),
            loadButton.trailingAnchor.constraint(equalTo: loadROMContainer.trailingAnchor),
            loadButton.heightAnchor.constraint(equalToConstant: 56),

            recentsLabel.topAnchor.constraint(equalTo: loadButton.bottomAnchor, constant: 30),
            recentsLabel.leadingAnchor.constraint(equalTo: loadROMContainer.leadingAnchor),

            recentsTableView.topAnchor.constraint(equalTo: recentsLabel.bottomAnchor, constant: 8),
            recentsTableView.leadingAnchor.constraint(equalTo: loadROMContainer.leadingAnchor),
            recentsTableView.trailingAnchor.constraint(equalTo: loadROMContainer.trailingAnchor),
            recentsTableView.bottomAnchor.constraint(equalTo: loadROMContainer.bottomAnchor),
        ])
    }

    @objc private func loadROMTapped() {
        let picker = ROMPicker.make(delegate: self)
        present(picker, animated: true)
    }

    private func launchROM(at url: URL) {
        let name = url.deletingPathExtension().lastPathComponent
        let entry = ROMEntry(name: name, path: url.lastPathComponent)
        RecentROMs.shared.add(entry)

        if EmulatorCore.shared.loadROM(at: url) {
            hasROMLoaded = true
            showEmulator()
            if !TwoPhoneConfiguration.current.isTwoPhoneSession {
                AudioManager.shared.start()
            }
            ControllerManager.shared.setup()
        } else {
            print("TWO_PHONE_ROM_LOAD_FAILED \(url.path)")
        }
    }

    private func showEmulator() {
        UIView.animate(withDuration: 0.3) {
            self.loadROMContainer.alpha = 0
        } completion: { _ in
            self.loadROMContainer.isHidden = true
            self.screenBezel.isHidden = false
            self.onScreenControls?.isHidden = false
            self.applyLayoutForCurrentOrientation()
        }
    }

    // MARK: - Touch Input (DS Touchscreen)

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard hasROMLoaded, let touch = touches.first else { return }
        let point = touch.location(in: screenView)
        if let (x, y) = screenView.mapTouchToDS(point: point) {
            EmulatorCore.shared.touchScreen(x: x, y: y)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard hasROMLoaded, let touch = touches.first else { return }
        let point = touch.location(in: screenView)
        if let (x, y) = screenView.mapTouchToDS(point: point) {
            EmulatorCore.shared.touchScreen(x: x, y: y)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard hasROMLoaded else { return }
        EmulatorCore.shared.releaseScreen()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard hasROMLoaded else { return }
        EmulatorCore.shared.releaseScreen()
    }

    // MARK: - On-Screen Controls

    private var onScreenControls: OnScreenControls?

    private func setupOnScreenControls() {
        let controls = OnScreenControls()
        controls.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controls)
        onScreenControls = controls
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
}

// MARK: - ROM Picker Delegate

extension BottomScreenViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let destURL = docsDir.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: destURL)
        try? FileManager.default.copyItem(at: url, to: destURL)

        launchROM(at: destURL)
    }
}

// MARK: - Recents Table

extension BottomScreenViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        recents.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "rom", for: indexPath)
        let entry = recents[indexPath.row]
        cell.textLabel?.text = entry.name
        cell.textLabel?.textColor = .white
        cell.backgroundColor = .clear
        cell.imageView?.image = UIImage(systemName: "gamecontroller.fill")
        cell.imageView?.tintColor = UIColor(red: 0.2, green: 0.5, blue: 1.0, alpha: 1.0)
        cell.selectionStyle = .gray
        let bg = UIView()
        bg.backgroundColor = UIColor.white.withAlphaComponent(0.1)
        cell.selectedBackgroundView = bg
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let entry = recents[indexPath.row]
        let url = RecentROMs.shared.urlFor(entry)
        launchROM(at: url)
    }
}

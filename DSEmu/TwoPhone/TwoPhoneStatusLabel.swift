import UIKit

final class TwoPhoneStatusLabel: UILabel {
    private var observer: NSObjectProtocol?

    init(role: TwoPhoneRole) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        text = role == .controller ? "Controller: loading" : "Top display: loading"
        textColor = .white
        backgroundColor = .clear
        font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        textAlignment = .center
        numberOfLines = 2

        observer = NotificationCenter.default.addObserver(
            forName: .twoPhoneStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.text = notification.userInfo?["message"] as? String
        }
    }

    required init?(coder: NSCoder) { nil }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }
}

extension UIViewController {
    func installTwoPhoneStatusLabelIfNeeded() {
        let role = TwoPhoneConfiguration.current.role
        guard role != .standalone else { return }

        let label = TwoPhoneStatusLabel(role: role)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let setupButton = UIButton(type: .system)
        setupButton.setTitle("Setup", for: .normal)
        setupButton.setTitleColor(.white, for: .normal)
        setupButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .bold)
        setupButton.backgroundColor = UIColor.white.withAlphaComponent(0.16)
        setupButton.layer.cornerRadius = 7
        setupButton.accessibilityLabel = "Change two-phone setup"
        setupButton.addAction(UIAction { [weak self] _ in
            self?.confirmTwoPhoneSetupReset()
        }, for: .touchUpInside)

        let statusBar = UIStackView(arrangedSubviews: [label, setupButton])
        statusBar.translatesAutoresizingMaskIntoConstraints = false
        statusBar.axis = .horizontal
        statusBar.spacing = 8
        statusBar.alignment = .center
        statusBar.isLayoutMarginsRelativeArrangement = true
        statusBar.layoutMargins = UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 4)
        statusBar.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        statusBar.layer.cornerRadius = 10
        statusBar.layer.masksToBounds = true
        view.addSubview(statusBar)

        NSLayoutConstraint.activate([
            statusBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            statusBar.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusBar.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.94),
            statusBar.heightAnchor.constraint(greaterThanOrEqualToConstant: 40),
            setupButton.widthAnchor.constraint(equalToConstant: 62),
            setupButton.heightAnchor.constraint(equalToConstant: 32),
        ])
    }

    private func confirmTwoPhoneSetupReset() {
        let alert = UIAlertController(
            title: "Change this phone’s job?",
            message: "Reset the saved role and ROM, then force-quit and reopen TwoPhone DS to run setup again.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Reset Setup", style: .destructive) { _ in
            TwoPhonePreferences.shared.reset()
        })
        present(alert, animated: true)
    }
}

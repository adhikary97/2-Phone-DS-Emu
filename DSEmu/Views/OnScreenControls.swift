import UIKit

class OnScreenControls: UIView {

    private enum DSButton: Int {
        case a = 0, b = 1, select = 2, start = 3
        case right = 4, left = 5, up = 6, down = 7
        case r = 8, l = 9, x = 10, y = 11
    }

    private var buttonMask: UInt32 = 0xFFF

    // Sub-containers for layout switching
    private let leftGroup = UIView()   // D-pad + L
    private let rightGroup = UIView()  // Face buttons + R
    private let centerGroup = UIView() // Start/Select

    private var portraitConstraints: [NSLayoutConstraint] = []
    private var landscapeConstraints: [NSLayoutConstraint] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .clear
        isUserInteractionEnabled = true

        for g in [leftGroup, rightGroup, centerGroup] {
            g.translatesAutoresizingMaskIntoConstraints = false
            addSubview(g)
        }

        // D-Pad in left group
        let dpad = createDPad()
        dpad.translatesAutoresizingMaskIntoConstraints = false
        leftGroup.addSubview(dpad)

        let lBtn = createButton(title: "L", tag: DSButton.l.rawValue)
        lBtn.translatesAutoresizingMaskIntoConstraints = false
        leftGroup.addSubview(lBtn)

        NSLayoutConstraint.activate([
            lBtn.topAnchor.constraint(equalTo: leftGroup.topAnchor),
            lBtn.centerXAnchor.constraint(equalTo: leftGroup.centerXAnchor),
            dpad.topAnchor.constraint(equalTo: lBtn.bottomAnchor, constant: 8),
            dpad.centerXAnchor.constraint(equalTo: leftGroup.centerXAnchor),
            dpad.bottomAnchor.constraint(lessThanOrEqualTo: leftGroup.bottomAnchor),
            leftGroup.widthAnchor.constraint(equalToConstant: 160),
        ])

        // Face buttons in right group
        let face = createFaceButtons()
        face.translatesAutoresizingMaskIntoConstraints = false
        rightGroup.addSubview(face)

        let rBtn = createButton(title: "R", tag: DSButton.r.rawValue)
        rBtn.translatesAutoresizingMaskIntoConstraints = false
        rightGroup.addSubview(rBtn)

        NSLayoutConstraint.activate([
            rBtn.topAnchor.constraint(equalTo: rightGroup.topAnchor),
            rBtn.centerXAnchor.constraint(equalTo: rightGroup.centerXAnchor),
            face.topAnchor.constraint(equalTo: rBtn.bottomAnchor, constant: 8),
            face.centerXAnchor.constraint(equalTo: rightGroup.centerXAnchor),
            face.bottomAnchor.constraint(lessThanOrEqualTo: rightGroup.bottomAnchor),
            rightGroup.widthAnchor.constraint(equalToConstant: 160),
        ])

        // Start/Select in center group
        let menu = createMenuButtons()
        menu.translatesAutoresizingMaskIntoConstraints = false
        centerGroup.addSubview(menu)

        NSLayoutConstraint.activate([
            menu.centerXAnchor.constraint(equalTo: centerGroup.centerXAnchor),
            menu.centerYAnchor.constraint(equalTo: centerGroup.centerYAnchor),
        ])

        // Portrait: all at bottom, left/right spread, center below
        portraitConstraints = [
            leftGroup.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            leftGroup.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            leftGroup.heightAnchor.constraint(equalToConstant: 190),

            rightGroup.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            rightGroup.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            rightGroup.heightAnchor.constraint(equalToConstant: 190),

            centerGroup.centerXAnchor.constraint(equalTo: centerXAnchor),
            centerGroup.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            centerGroup.widthAnchor.constraint(equalToConstant: 180),
            centerGroup.heightAnchor.constraint(equalToConstant: 40),
        ]

        // Landscape: left group on left edge, right group on right edge, center at bottom-center
        landscapeConstraints = [
            leftGroup.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 5),
            leftGroup.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 10),
            leftGroup.heightAnchor.constraint(equalToConstant: 190),

            rightGroup.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -5),
            rightGroup.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 10),
            rightGroup.heightAnchor.constraint(equalToConstant: 190),

            centerGroup.centerXAnchor.constraint(equalTo: centerXAnchor),
            centerGroup.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -2),
            centerGroup.widthAnchor.constraint(equalToConstant: 180),
            centerGroup.heightAnchor.constraint(equalToConstant: 40),
        ]

        NSLayoutConstraint.activate(portraitConstraints)
    }

    func setLandscape(_ landscape: Bool) {
        NSLayoutConstraint.deactivate(portraitConstraints)
        NSLayoutConstraint.deactivate(landscapeConstraints)
        NSLayoutConstraint.activate(landscape ? landscapeConstraints : portraitConstraints)
    }

    // MARK: - Button Factories

    private func createDPad() -> UIView {
        let container = UIView()
        let size: CGFloat = 48

        let up = createButton(title: "^", tag: DSButton.up.rawValue)
        let down = createButton(title: "v", tag: DSButton.down.rawValue)
        let left = createButton(title: "<", tag: DSButton.left.rawValue)
        let right = createButton(title: ">", tag: DSButton.right.rawValue)

        for btn in [up, down, left, right] {
            btn.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(btn)
            NSLayoutConstraint.activate([
                btn.widthAnchor.constraint(equalToConstant: size),
                btn.heightAnchor.constraint(equalToConstant: size),
            ])
        }

        NSLayoutConstraint.activate([
            up.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            up.topAnchor.constraint(equalTo: container.topAnchor),
            down.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            down.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            left.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            left.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            right.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            right.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            container.widthAnchor.constraint(equalToConstant: size * 3),
            container.heightAnchor.constraint(equalToConstant: size * 3),
        ])

        return container
    }

    private func createFaceButtons() -> UIView {
        let container = UIView()
        let size: CGFloat = 48

        let x = createButton(title: "X", tag: DSButton.x.rawValue)
        let y = createButton(title: "Y", tag: DSButton.y.rawValue)
        let a = createButton(title: "A", tag: DSButton.a.rawValue)
        let b = createButton(title: "B", tag: DSButton.b.rawValue)

        for btn in [x, y, a, b] {
            btn.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(btn)
            NSLayoutConstraint.activate([
                btn.widthAnchor.constraint(equalToConstant: size),
                btn.heightAnchor.constraint(equalToConstant: size),
            ])
        }

        NSLayoutConstraint.activate([
            x.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            x.topAnchor.constraint(equalTo: container.topAnchor),
            b.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            b.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            y.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            y.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            a.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            a.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            container.widthAnchor.constraint(equalToConstant: size * 3),
            container.heightAnchor.constraint(equalToConstant: size * 3),
        ])

        return container
    }

    private func createMenuButtons() -> UIView {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 16

        let sel = createButton(title: "SELECT", tag: DSButton.select.rawValue)
        let start = createButton(title: "START", tag: DSButton.start.rawValue)

        sel.widthAnchor.constraint(equalToConstant: 70).isActive = true
        start.widthAnchor.constraint(equalToConstant: 70).isActive = true
        sel.heightAnchor.constraint(equalToConstant: 30).isActive = true
        start.heightAnchor.constraint(equalToConstant: 30).isActive = true

        stack.addArrangedSubview(sel)
        stack.addArrangedSubview(start)
        return stack
    }

    private func createButton(title: String, tag: Int) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.tag = tag
        button.titleLabel?.font = .boldSystemFont(ofSize: 14)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = UIColor.white.withAlphaComponent(0.2)
        button.layer.cornerRadius = 8
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor.white.withAlphaComponent(0.4).cgColor

        button.addTarget(self, action: #selector(buttonDown(_:)), for: .touchDown)
        button.addTarget(self, action: #selector(buttonUp(_:)), for: [.touchUpInside, .touchUpOutside, .touchCancel])

        return button
    }

    @objc private func buttonDown(_ sender: UIButton) {
        buttonMask &= ~(UInt32(1) << sender.tag)
        EmulatorCore.shared.setKeyMask(buttonMask)
        sender.backgroundColor = UIColor.white.withAlphaComponent(0.5)
    }

    @objc private func buttonUp(_ sender: UIButton) {
        buttonMask |= (UInt32(1) << sender.tag)
        EmulatorCore.shared.setKeyMask(buttonMask)
        sender.backgroundColor = UIColor.white.withAlphaComponent(0.2)
    }
}

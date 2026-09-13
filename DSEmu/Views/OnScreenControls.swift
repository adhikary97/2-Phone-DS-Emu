import UIKit

private final class DSControlButton: UIButton {
    override func layoutSubviews() {
        super.layoutSubviews()
        guard layer.shadowOpacity > 0, !bounds.isEmpty else { return }
        layer.shadowPath = UIBezierPath(
            roundedRect: bounds,
            cornerRadius: layer.cornerRadius
        ).cgPath
    }
}

class OnScreenControls: UIView {

    private enum Palette {
        static let dpad = UIColor(red: 0.105, green: 0.111, blue: 0.126, alpha: 1)
        static let face = UIColor(red: 0.310, green: 0.325, blue: 0.355, alpha: 1)
        static let shoulder = UIColor(red: 0.255, green: 0.270, blue: 0.300, alpha: 1)
        static let menu = UIColor(red: 0.115, green: 0.121, blue: 0.137, alpha: 1)
        static let controlEdge = UIColor.white.withAlphaComponent(0.20)
        static let pressed = UIColor(red: 0.430, green: 0.450, blue: 0.490, alpha: 1)
        static let label = UIColor(red: 0.930, green: 0.925, blue: 0.900, alpha: 1)
        static let dpadLabel = UIColor.white.withAlphaComponent(0.54)
    }

    private enum DSButton: Int {
        case a = 0, b = 1, select = 2, start = 3
        case right = 4, left = 5, up = 6, down = 7
        case r = 8, l = 9, x = 10, y = 11
    }

    private var buttonMask: UInt32 = 0xFFF

    // Menu buttons live in the side wings so the center lane belongs entirely
    // to the DS screen.
    private let leftGroup = UIView()   // D-pad + L + Select
    private let rightGroup = UIView()  // Face buttons + R + Start

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

        for g in [leftGroup, rightGroup] {
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

        let selectButton = createButton(title: "SELECT", tag: DSButton.select.rawValue)
        selectButton.translatesAutoresizingMaskIntoConstraints = false
        leftGroup.addSubview(selectButton)

        NSLayoutConstraint.activate([
            lBtn.topAnchor.constraint(equalTo: leftGroup.topAnchor, constant: 10),
            lBtn.centerXAnchor.constraint(equalTo: leftGroup.centerXAnchor),
            lBtn.widthAnchor.constraint(equalToConstant: 112),
            lBtn.heightAnchor.constraint(equalToConstant: 30),
            dpad.centerXAnchor.constraint(equalTo: leftGroup.centerXAnchor),
            dpad.centerYAnchor.constraint(equalTo: leftGroup.centerYAnchor),
            selectButton.centerXAnchor.constraint(equalTo: leftGroup.centerXAnchor),
            selectButton.widthAnchor.constraint(equalToConstant: 64),
            selectButton.heightAnchor.constraint(equalToConstant: 26),
            selectButton.bottomAnchor.constraint(equalTo: leftGroup.bottomAnchor, constant: -10),
            leftGroup.widthAnchor.constraint(equalToConstant: 140),
        ])

        // Face buttons in right group
        let face = createFaceButtons()
        face.translatesAutoresizingMaskIntoConstraints = false
        rightGroup.addSubview(face)

        let rBtn = createButton(title: "R", tag: DSButton.r.rawValue)
        rBtn.translatesAutoresizingMaskIntoConstraints = false
        rightGroup.addSubview(rBtn)

        let startButton = createButton(title: "START", tag: DSButton.start.rawValue)
        startButton.translatesAutoresizingMaskIntoConstraints = false
        rightGroup.addSubview(startButton)

        NSLayoutConstraint.activate([
            rBtn.topAnchor.constraint(equalTo: rightGroup.topAnchor, constant: 10),
            rBtn.centerXAnchor.constraint(equalTo: rightGroup.centerXAnchor),
            rBtn.widthAnchor.constraint(equalToConstant: 112),
            rBtn.heightAnchor.constraint(equalToConstant: 30),
            face.centerXAnchor.constraint(equalTo: rightGroup.centerXAnchor),
            face.centerYAnchor.constraint(equalTo: rightGroup.centerYAnchor),
            startButton.centerXAnchor.constraint(equalTo: rightGroup.centerXAnchor),
            startButton.widthAnchor.constraint(equalToConstant: 64),
            startButton.heightAnchor.constraint(equalToConstant: 26),
            startButton.bottomAnchor.constraint(equalTo: rightGroup.bottomAnchor, constant: -10),
            rightGroup.widthAnchor.constraint(equalToConstant: 140),
        ])

        // Portrait: both control wings sit on the lower deck.
        portraitConstraints = [
            leftGroup.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            leftGroup.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            leftGroup.heightAnchor.constraint(equalToConstant: 280),

            rightGroup.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            rightGroup.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            rightGroup.heightAnchor.constraint(equalToConstant: 280),
        ]

        // Landscape: use the full height of the side lanes. Shoulders stay at
        // the top, primary controls remain centered, and menu buttons sit at
        // the bottom so a stray thumb cannot easily cross between zones.
        landscapeConstraints = [
            leftGroup.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 4),
            leftGroup.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 8),
            leftGroup.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -8),

            rightGroup.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -4),
            rightGroup.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 8),
            rightGroup.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -8),
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
        let size: CGFloat = 44
        container.accessibilityIdentifier = "controller.dpad.cross"

        // Overlapping rails create a single connected cross silhouette while
        // the four ends remain independent touch targets.
        let verticalRail = makeDPadRail()
        let horizontalRail = makeDPadRail()
        container.addSubview(verticalRail)
        container.addSubview(horizontalRail)

        NSLayoutConstraint.activate([
            verticalRail.topAnchor.constraint(equalTo: container.topAnchor),
            verticalRail.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            verticalRail.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            verticalRail.widthAnchor.constraint(equalToConstant: size),
            horizontalRail.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            horizontalRail.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            horizontalRail.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            horizontalRail.heightAnchor.constraint(equalToConstant: size),
        ])

        container.layer.shadowColor = UIColor.black.cgColor
        container.layer.shadowOpacity = 0.48
        container.layer.shadowRadius = 3
        container.layer.shadowOffset = CGSize(width: 0, height: 3)
        let crossShadow = UIBezierPath(
            roundedRect: CGRect(x: size, y: 0, width: size, height: size * 3),
            cornerRadius: 6
        )
        crossShadow.append(UIBezierPath(
            roundedRect: CGRect(x: 0, y: size, width: size * 3, height: size),
            cornerRadius: 6
        ))
        container.layer.shadowPath = crossShadow.cgPath

        let pivot = UIView()
        pivot.translatesAutoresizingMaskIntoConstraints = false
        pivot.backgroundColor = UIColor.white.withAlphaComponent(0.035)
        pivot.layer.cornerRadius = 8
        container.addSubview(pivot)
        NSLayoutConstraint.activate([
            pivot.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            pivot.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            pivot.widthAnchor.constraint(equalToConstant: 16),
            pivot.heightAnchor.constraint(equalToConstant: 16),
        ])

        let up = createButton(title: "▲", tag: DSButton.up.rawValue)
        let down = createButton(title: "▼", tag: DSButton.down.rawValue)
        let left = createButton(title: "◀", tag: DSButton.left.rawValue)
        let right = createButton(title: "▶", tag: DSButton.right.rawValue)

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

    private func makeDPadRail() -> UIView {
        let rail = UIView()
        rail.translatesAutoresizingMaskIntoConstraints = false
        rail.backgroundColor = Palette.dpad
        rail.layer.cornerRadius = 6
        rail.layer.cornerCurve = .continuous
        return rail
    }

    private func createFaceButtons() -> UIView {
        let container = UIView()
        let size: CGFloat = 44

        let x = createButton(title: "X", tag: DSButton.x.rawValue)
        let y = createButton(title: "Y", tag: DSButton.y.rawValue)
        let a = createButton(title: "A", tag: DSButton.a.rawValue)
        let b = createButton(title: "B", tag: DSButton.b.rawValue)

        for btn in [x, y, a, b] {
            btn.translatesAutoresizingMaskIntoConstraints = false
            btn.layer.cornerRadius = size / 2
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
            container.widthAnchor.constraint(equalToConstant: 120),
            container.heightAnchor.constraint(equalToConstant: 120),
        ])

        return container
    }

    private func createButton(title: String, tag: Int) -> UIButton {
        let button = DSControlButton(type: .custom)
        button.setTitle(title, for: .normal)
        button.tag = tag
        button.isExclusiveTouch = true

        let buttonKind = DSButton(rawValue: tag)
        let fontSize: CGFloat
        let fontWeight: UIFont.Weight
        switch buttonKind {
        case .select, .start:
            fontSize = 8
            fontWeight = .semibold
        case .l, .r:
            fontSize = 12
            fontWeight = .bold
        default:
            fontSize = 14
            fontWeight = .bold
        }

        let baseFont = UIFont.systemFont(ofSize: fontSize, weight: fontWeight)
        if let descriptor = baseFont.fontDescriptor.withDesign(.rounded) {
            button.titleLabel?.font = UIFont(descriptor: descriptor, size: baseFont.pointSize)
        } else {
            button.titleLabel?.font = baseFont
        }
        button.layer.cornerCurve = .continuous

        switch buttonKind {
        case .a, .b, .x, .y:
            // Raised circular caps echo the DS face-button cluster.
            button.setTitleColor(Palette.label, for: .normal)
            button.backgroundColor = Palette.face
            button.layer.cornerRadius = 22
            applyRaisedEdge(to: button, shadowDepth: 3)
        case .right, .left, .up, .down:
            // The cross rails supply the body; each transparent end supplies
            // an arrow and an independent pressed state.
            button.setTitleColor(Palette.dpadLabel, for: .normal)
            button.backgroundColor = .clear
            button.layer.cornerRadius = 4
        case .l, .r:
            button.setTitleColor(Palette.label, for: .normal)
            button.backgroundColor = Palette.shoulder
            button.layer.cornerRadius = 9
            applyRaisedEdge(to: button, shadowDepth: 2)
        case .select, .start:
            button.setTitleColor(Palette.label.withAlphaComponent(0.82), for: .normal)
            button.backgroundColor = Palette.menu
            button.layer.cornerRadius = 13
            applyRaisedEdge(to: button, shadowDepth: 1)
        case .none:
            button.setTitleColor(Palette.label, for: .normal)
            button.backgroundColor = Palette.face
            button.layer.cornerRadius = 10
            applyRaisedEdge(to: button, shadowDepth: 2)
        }

        button.accessibilityIdentifier = "controller.\(tag)"

        button.addTarget(self, action: #selector(buttonDown(_:)), for: .touchDown)
        button.addTarget(self, action: #selector(buttonUp(_:)), for: [.touchUpInside, .touchUpOutside, .touchCancel])

        return button
    }

    private func applyRaisedEdge(to button: UIButton, shadowDepth: CGFloat) {
        button.layer.borderWidth = 1
        button.layer.borderColor = Palette.controlEdge.cgColor
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.44
        button.layer.shadowRadius = 2
        button.layer.shadowOffset = CGSize(width: 0, height: shadowDepth)
    }

    private func restingColor(for tag: Int) -> UIColor {
        switch DSButton(rawValue: tag) {
        case .a, .b, .x, .y:
            return Palette.face
        case .right, .left, .up, .down:
            return .clear
        case .l, .r:
            return Palette.shoulder
        case .select, .start:
            return Palette.menu
        case .none:
            return Palette.face
        }
    }

    @objc private func buttonDown(_ sender: UIButton) {
        buttonMask &= ~(UInt32(1) << sender.tag)
        EmulatorCore.shared.setKeyMask(buttonMask)
        sender.backgroundColor = Palette.pressed
        sender.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
    }

    @objc private func buttonUp(_ sender: UIButton) {
        buttonMask |= (UInt32(1) << sender.tag)
        EmulatorCore.shared.setKeyMask(buttonMask)
        sender.backgroundColor = restingColor(for: sender.tag)
        sender.transform = .identity
    }
}

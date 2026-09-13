import GameController

final class ControllerManager {
    static let shared = ControllerManager()

    // DS button mask: bit=1 means NOT pressed
    // Bits: 0=A, 1=B, 2=Select, 3=Start, 4=Right, 5=Left, 6=Up, 7=Down, 8=R, 9=L, 10=X, 11=Y
    private var buttonMask: UInt32 = 0xFFF  // all released

    var onControllerConnected: (() -> Void)?
    var onControllerDisconnected: (() -> Void)?

    private init() {}

    func setup() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(controllerConnected),
            name: .GCControllerDidConnect,
            object: nil)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(controllerDisconnected),
            name: .GCControllerDidDisconnect,
            object: nil)

        GCController.startWirelessControllerDiscovery {}

        // Configure any already-connected controllers
        for controller in GCController.controllers() {
            configureController(controller)
        }
    }

    @objc private func controllerConnected(_ note: Notification) {
        guard let controller = note.object as? GCController else { return }
        configureController(controller)
        onControllerConnected?()
    }

    @objc private func controllerDisconnected(_ note: Notification) {
        buttonMask = 0xFFF
        EmulatorCore.shared.setKeyMask(buttonMask)
        onControllerDisconnected?()
    }

    private func configureController(_ controller: GCController) {
        guard let gamepad = controller.extendedGamepad else { return }

        gamepad.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.setButton(bit: 0, pressed: pressed)  // DS A
        }
        gamepad.buttonB.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.setButton(bit: 1, pressed: pressed)  // DS B
        }
        gamepad.buttonX.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.setButton(bit: 10, pressed: pressed) // DS X
        }
        gamepad.buttonY.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.setButton(bit: 11, pressed: pressed) // DS Y
        }
        gamepad.leftShoulder.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.setButton(bit: 9, pressed: pressed)  // DS L
        }
        gamepad.rightShoulder.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.setButton(bit: 8, pressed: pressed)  // DS R
        }
        gamepad.buttonMenu.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.setButton(bit: 3, pressed: pressed)  // DS Start
        }
        gamepad.buttonOptions?.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.setButton(bit: 2, pressed: pressed)  // DS Select
        }
        gamepad.dpad.valueChangedHandler = { [weak self] _, xValue, yValue in
            self?.setButton(bit: 4, pressed: xValue > 0.5)   // Right
            self?.setButton(bit: 5, pressed: xValue < -0.5)  // Left
            self?.setButton(bit: 6, pressed: yValue > 0.5)   // Up
            self?.setButton(bit: 7, pressed: yValue < -0.5)  // Down
        }
    }

    private func setButton(bit: Int, pressed: Bool) {
        if pressed {
            buttonMask &= ~(UInt32(1) << bit)   // Clear bit = pressed
        } else {
            buttonMask |= (UInt32(1) << bit)    // Set bit = released
        }
        EmulatorCore.shared.setKeyMask(buttonMask)
    }

    var hasConnectedController: Bool {
        !GCController.controllers().isEmpty
    }
}

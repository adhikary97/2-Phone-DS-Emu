import CryptoKit
import Foundation
import QuartzCore
import UIKit

extension Notification.Name {
    static let twoPhoneStatusDidChange = Notification.Name("TwoPhoneStatusDidChange")
}

enum EmulatorCoreError: Error, CustomStringConvertible {
    case snapshotCreationFailed
    case snapshotLoadFailed

    var description: String {
        switch self {
        case .snapshotCreationFailed: return "melonDS could not create an in-memory snapshot"
        case .snapshotLoadFailed: return "melonDS could not load the shared snapshot"
        }
    }
}

final class EmulatorCore {
    static let shared = EmulatorCore()

    private(set) var isRunning = false
    private var emuThread: Thread?
    private var stopRequested = false
    private var backgrounded = false
    private var loadedROMHash = Data()

    private let inputLock = NSLock()
    private var pendingKeyMask: UInt16 = 0x0FFF
    private var pendingTouch: (x: UInt16, y: UInt16)?

    // Renderers for each screen. In two-phone mode the controller uses the
    // bottom renderer and the display uses the top renderer.
    var phoneRenderer: MetalRenderer?
    var externalRenderer: MetalRenderer?

    private let dataDir: String = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.path
    }()

    private init() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    @objc private func appDidEnterBackground() {
        guard isRunning else { return }
        backgrounded = true
        melonds_pause()
        AudioManager.shared.stop()
    }

    @objc private func appWillEnterForeground() {
        guard backgrounded else { return }
        backgrounded = false
        melonds_resume()
        if !TwoPhoneConfiguration.current.isTwoPhoneSession {
            AudioManager.shared.start()
        }
    }

    func initialize() -> Bool {
        dataDir.withCString { platform_set_data_dir($0) }
        return melonds_init(dataDir)
    }

    func loadROM(at url: URL) -> Bool {
        guard emuThread == nil, let romData = try? Data(contentsOf: url) else { return false }

        let sramURL = URL(fileURLWithPath: dataDir).appendingPathComponent("save.sav")
        let sramData = try? Data(contentsOf: sramURL)
        let success = romData.withUnsafeBytes { romPointer -> Bool in
            guard let romBase = romPointer.baseAddress else { return false }
            let rom = romBase.assumingMemoryBound(to: UInt8.self)
            if let sramData {
                return sramData.withUnsafeBytes { sramPointer -> Bool in
                    guard let sramBase = sramPointer.baseAddress else { return false }
                    return melonds_load_rom(
                        rom,
                        UInt32(romData.count),
                        sramBase.assumingMemoryBound(to: UInt8.self),
                        UInt32(sramData.count)
                    )
                }
            }
            return melonds_load_rom(rom, UInt32(romData.count), nil, 0)
        }

        if success {
            loadedROMHash = Data(SHA256.hash(data: romData))
            isRunning = true
            stopRequested = false
            startEmulationLoop()
        }
        return success
    }

    func pause() {
        melonds_pause()
        isRunning = false
    }

    func resume() {
        melonds_resume()
        isRunning = true
    }

    func reset() { melonds_reset() }

    func setKeyMask(_ mask: UInt32) {
        inputLock.lock()
        pendingKeyMask = UInt16(truncatingIfNeeded: mask) & 0x0FFF
        inputLock.unlock()
    }

    func touchScreen(x: UInt16, y: UInt16) {
        inputLock.lock()
        pendingTouch = (min(x, 255), min(y, 191))
        inputLock.unlock()
    }

    func releaseScreen() {
        inputLock.lock()
        pendingTouch = nil
        inputLock.unlock()
    }

    func saveState(slot: Int) -> Bool {
        let path = URL(fileURLWithPath: dataDir).appendingPathComponent("SaveStates", isDirectory: true)
        try? FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        return melonds_save_state(path.appendingPathComponent("slot_\(slot).mst").path)
    }

    func loadState(slot: Int) -> Bool {
        let file = URL(fileURLWithPath: dataDir)
            .appendingPathComponent("SaveStates")
            .appendingPathComponent("slot_\(slot).mst").path
        return melonds_load_state(file)
    }

    private func startEmulationLoop() {
        let thread = Thread { [weak self] in self?.emulationLoop() }
        thread.name = "DSEmu.Emulation"
        thread.qualityOfService = .userInteractive
        thread.start()
        emuThread = thread
    }

    private func emulationLoop() {
        let configuration = TwoPhoneConfiguration.current
        if configuration.isTwoPhoneSession {
            runTwoPhoneSession(configuration: configuration)
        } else {
            runStandaloneLoop()
        }
    }

    private func runStandaloneLoop() {
        let targetFrameTime = 1.0 / 60.0
        var frame: UInt64 = 0
        while !stopRequested {
            guard melonds_is_running(), !backgrounded else {
                Thread.sleep(forTimeInterval: 0.05)
                continue
            }

            let frameStart = CACurrentMediaTime()
            frame += 1
            step(input: currentInput(frame: frame), createDigest: false)
            let remaining = targetFrameTime - (CACurrentMediaTime() - frameStart)
            if remaining > 0 { Thread.sleep(forTimeInterval: remaining) }
        }
    }

    private func runTwoPhoneSession(configuration: TwoPhoneConfiguration) {
        let startedAt = Date()
        let session = TwoPhoneSession(
            configuration: configuration,
            romSHA256: loadedROMHash,
            makeSnapshot: { [weak self] in
                guard let self else { throw EmulatorCoreError.snapshotCreationFailed }
                return try self.makeSnapshot()
            },
            loadSnapshot: { [weak self] snapshot in
                guard let self else { throw EmulatorCoreError.snapshotLoadFailed }
                try self.loadSnapshot(snapshot)
            },
            inputProvider: { [weak self] frame in
                guard let self else {
                    return DSInputFrame(frame: frame, keyMask: 0x0FFF, touchX: 0, touchY: 0, touchActive: false)
                }
                if configuration.scriptedInputs { return TwoPhoneInputScript.input(frame: frame) }
                return self.currentInput(frame: frame)
            },
            stepFrame: { [weak self] input, createDigest in
                self?.step(input: input, createDigest: createDigest)
            },
            status: { [weak self] message in self?.publishStatus(message) }
        )

        let outcome: TwoPhoneSessionOutcome
        do {
            outcome = try session.run()
        } catch {
            publishStatus("Session failed: \(error)")
            outcome = TwoPhoneSessionOutcome(
                success: false,
                framesCompleted: 0,
                finalDigest: nil,
                checkpointsCompared: 0,
                snapshotBytes: 0,
                detail: String(describing: error)
            )
        }

        if configuration.isAutomatedProof {
            let elapsed = Date().timeIntervalSince(startedAt)
            let report = TwoPhoneTestReport(
                role: configuration.role,
                success: outcome.success,
                framesCompleted: outcome.framesCompleted,
                elapsedSeconds: elapsed,
                framesPerSecond: elapsed > 0 ? Double(outcome.framesCompleted) / elapsed : 0,
                romSHA256: loadedROMHash.map { String(format: "%02x", $0) }.joined(),
                finalDigest: outcome.finalDigest,
                checkpointsCompared: outcome.checkpointsCompared,
                snapshotBytes: outcome.snapshotBytes,
                detail: outcome.detail
            )
            TwoPhoneTestReportWriter.write(report)
        }
        isRunning = false
    }

    @discardableResult
    private func step(input: DSInputFrame, createDigest: Bool) -> EmulatorDigest? {
        melonds_set_key_mask(UInt32(input.keyMask))
        if input.touchActive {
            melonds_touch_screen(input.touchX, input.touchY)
        } else {
            melonds_release_screen()
        }
        melonds_run_frame()

        var topPointer: UnsafePointer<UInt32>?
        var bottomPointer: UnsafePointer<UInt32>?
        melonds_get_framebuffers(&topPointer, &bottomPointer)
        if !backgrounded {
            render(top: topPointer, bottom: bottomPointer)
        }

        guard createDigest else { return nil }
        return EmulatorDigest(
            frame: input.frame,
            state: melonds_state_hash(),
            top: melonds_top_framebuffer_hash(),
            bottom: melonds_bottom_framebuffer_hash()
        )
    }

    private func render(top: UnsafePointer<UInt32>?, bottom: UnsafePointer<UInt32>?) {
        switch TwoPhoneConfiguration.current.role {
        case .controller:
            if let bottom, let renderer = phoneRenderer {
                renderer.updateTexture(with: bottom)
                renderer.draw()
            }
        case .display:
            if let top, let renderer = externalRenderer {
                renderer.updateTexture(with: top)
                renderer.draw()
            }
        case .standalone:
            if let bottom, let renderer = phoneRenderer {
                renderer.updateTexture(with: bottom)
                renderer.draw()
            }
            if let top, let renderer = externalRenderer {
                renderer.updateTexture(with: top)
                renderer.draw()
            }
        }
    }

    private func currentInput(frame: UInt64) -> DSInputFrame {
        inputLock.lock()
        let keyMask = pendingKeyMask
        let touch = pendingTouch
        inputLock.unlock()
        return DSInputFrame(
            frame: frame,
            keyMask: keyMask,
            touchX: touch?.x ?? 0,
            touchY: touch?.y ?? 0,
            touchActive: touch != nil
        )
    }

    private func makeSnapshot() throws -> Data {
        let required = melonds_save_state_to_buffer(nil, 0)
        guard required > 0 else { throw EmulatorCoreError.snapshotCreationFailed }
        var snapshot = Data(count: Int(required))
        let written = snapshot.withUnsafeMutableBytes { bytes -> UInt32 in
            guard let base = bytes.baseAddress else { return 0 }
            return melonds_save_state_to_buffer(base.assumingMemoryBound(to: UInt8.self), required)
        }
        guard written == required else { throw EmulatorCoreError.snapshotCreationFailed }
        return snapshot
    }

    private func loadSnapshot(_ snapshot: Data) throws {
        let success = snapshot.withUnsafeBytes { bytes -> Bool in
            guard let base = bytes.baseAddress else { return false }
            return melonds_load_state_from_buffer(
                base.assumingMemoryBound(to: UInt8.self),
                UInt32(snapshot.count)
            )
        }
        guard success else { throw EmulatorCoreError.snapshotLoadFailed }
    }

    private func publishStatus(_ message: String) {
        print("TWO_PHONE_STATUS \(TwoPhoneConfiguration.current.role.rawValue) \(message)")
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .twoPhoneStatusDidChange,
                object: nil,
                userInfo: ["message": message]
            )
        }
    }

    func shutdown() {
        stopRequested = true
        emuThread = nil
        melonds_deinit()
        isRunning = false
    }
}

@_silgen_name("platform_set_data_dir")
func platform_set_data_dir(_ dir: UnsafePointer<CChar>?)


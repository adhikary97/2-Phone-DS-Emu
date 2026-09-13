import AVFoundation

final class AudioManager {
    static let shared = AudioManager()

    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private var isStarted = false

    // melonDS SPU outputs at ~32768 Hz stereo
    private let sampleRate: Double = 32768
    private let channels: UInt32 = 2

    private init() {}

    func start() {
        guard !isStarted else { return }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setPreferredSampleRate(sampleRate)
            try session.setActive(true)
        } catch {
            print("AudioManager: Failed to configure audio session: \(error)")
            return
        }

        let format = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                   sampleRate: sampleRate,
                                   channels: channels,
                                   interleaved: true)!

        let node = AVAudioSourceNode(format: format) { _, _, frameCount, bufferList -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(bufferList)
            guard abl.count > 0,
                  let data = abl[0].mData else { return noErr }

            let ptr = data.assumingMemoryBound(to: Int16.self)
            let samplesRead = melonds_audio_read(ptr, Int32(frameCount))

            // If we got fewer samples than requested, zero-fill the rest
            if samplesRead < Int(frameCount) {
                let offset = Int(samplesRead) * 2  // stereo
                let remaining = (Int(frameCount) - Int(samplesRead)) * 2
                ptr.advanced(by: offset).update(repeating: 0, count: remaining)
            }

            abl[0].mDataByteSize = UInt32(frameCount) * 2 * UInt32(MemoryLayout<Int16>.size)
            return noErr
        }

        sourceNode = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)

        do {
            try engine.start()
            isStarted = true
        } catch {
            print("AudioManager: Failed to start audio engine: \(error)")
        }
    }

    func stop() {
        guard isStarted else { return }
        engine.stop()
        if let node = sourceNode {
            engine.detach(node)
            sourceNode = nil
        }
        isStarted = false
    }
}

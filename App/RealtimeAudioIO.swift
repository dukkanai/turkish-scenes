import AVFoundation

/// All setup/teardown/playback calls occur on the main actor. The tap owns its converter.
@MainActor final class RealtimeAudioIO {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var tapInstalled = false
    private var attached = false
    private var sessionActive = false
    private var generation = UUID()
    private var timeline = AudioPlaybackTimeline()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)
    var onPCM: ((Data) -> Void)?
    var onFailure: ((AudioError) -> Void)?
    func start() throws {
        guard !tapInstalled, !engine.isRunning, let format else { throw AudioError.format }
        let token = UUID()
        generation = token
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)
        sessionActive = true
        let input = engine.inputNode
        try input.setVoiceProcessingEnabled(true)
        if !attached { engine.attach(player); attached = true }
        engine.connect(player, to: engine.mainMixerNode, format: format)
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0,
              let pcm = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24000, channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: inputFormat, to: pcm) else { throw AudioError.format }
        input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * 24000 / inputFormat.sampleRate)) + 32
            guard let output = AVAudioPCMBuffer(pcmFormat: pcm, frameCapacity: capacity) else {
                Task { @MainActor [weak self] in
                    guard let self, self.generation == token else { return }
                    self.onFailure?(.allocation)
                }
                return
            }
            var supplied = false
            var error: NSError?
            let conversion = converter.convert(to: output, error: &error) { _, status in
                if supplied { status.pointee = .noDataNow; return nil }
                supplied = true; status.pointee = .haveData; return buffer
            }
            guard error == nil, conversion != .error else {
                Task { @MainActor [weak self] in
                    guard let self, self.generation == token else { return }
                    self.onFailure?(.conversion)
                }
                return
            }
            // A converter may need more input before producing a frame.
            guard output.frameLength > 0 else { return }
            guard let bytes = output.audioBufferList.pointee.mBuffers.mData else {
                Task { @MainActor [weak self] in
                    guard let self, self.generation == token else { return }
                    self.onFailure?(.allocation)
                }
                return
            }
            let data = Data(bytes: bytes, count: Int(output.frameLength) * 2)
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.onPCM?(data)
            }
        }
        tapInstalled = true
        engine.prepare()
        try engine.start()
        player.play()
    }
    func play(_ data: Data, itemID: String) throws {
        guard engine.isRunning, let format, !data.isEmpty, data.count % 2 == 0, data.count <= 512_000 else { throw AudioError.format }
        let count = data.count / 2
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)),
              let samples = buffer.floatChannelData?[0] else { throw AudioError.format }
        buffer.frameLength = AVAudioFrameCount(count)
        data.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            for i in 0..<count {
                let value = Int16(bitPattern: UInt16(bytes[2*i]) | (UInt16(bytes[2*i+1]) << 8))
                samples[i] = Float(value) / 32768
            }
        }
        guard let start = timeline.append(itemID: itemID, frames: Int64(count), renderedFrame: renderedFrames) else {
            throw AudioError.overflow
        }
        // Preserve all earlier buffers, including the tail of another response item.
        player.scheduleBuffer(buffer, at: AVAudioTime(sampleTime: start, atRate: 24000), options: [])
    }
    private var renderedFrames: AVAudioFramePosition {
        guard let time = player.lastRenderTime, let value = player.playerTime(forNodeTime: time) else { return 0 }
        return max(0, value.sampleTime)
    }
    func interrupt() -> [(String, Int)] {
        let result = timeline.truncations(at: renderedFrames)
        player.stop(); timeline.reset()
        if engine.isRunning { player.play() }
        return result
    }
    @discardableResult func stop() -> AudioError? {
        generation = UUID() // Discard tap callbacks already queued before teardown.
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        player.stop(); engine.stop(); timeline.reset()
        guard sessionActive else { return nil }
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            sessionActive = false
        } catch { return .deactivation }
        return nil
    }
    enum AudioError: Error { case format, overflow, conversion, allocation, deactivation }
}

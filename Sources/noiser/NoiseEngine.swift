import AVFoundation
import CoreAudio
import Synchronization

enum PlayState: Int {
    case idle, playing, paused
}

@inline(__always)
func monotonicNow() -> Double {
    Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) / 1e9
}

/// Endless output stream; the UI only moves the gain target around.
///
/// Everything the render block reads is atomic. The render block is the only writer of the
/// filter state and the current gain; the UI thread is the only caller of the control methods.
final class NoiseEngine {
    static let sampleRate = 48_000.0
    // One-pole leak keeps brown noise (a random walk) from drifting into DC / clipping.
    static let leak = 0.999
    // Every noise type is normalized to this RMS so 0 dB sounds equally loud for all of them.
    // Brown noise has a crest factor around 4, so 0.22 leaves peaks just under full scale;
    // above that a tanh soft limiter takes over instead of hard clipping. Past roughly
    // +12 dB it stops adding loudness and only adds distortion, hence the slider ceiling.
    static let targetRMS = 0.22
    static let volumeMinDb = -30.0
    static let volumeMaxDb = 12.0
    static let defaultVolumeDb = 0.0
    static let fadeInSeconds = 3.0
    static let fadeOutSeconds = 5.0
    static let pauseFadeSeconds = 0.5
    // Colored noise piles its energy below what speakers reproduce; that inaudible sub-bass
    // would otherwise eat all the headroom (and drive the limiter), so it is cut off.
    // Raising the cutoff makes brown noise sound louder on small speakers at the cost of rumble.
    static let lowCutHz = 42.0

    // Shared between the UI thread and the render thread.
    private let stateRaw = Atomic<Int>(PlayState.idle.rawValue)
    private let deadline = Atomic<Double>(0)  // monotonic seconds; 0 means no timer
    private let target = Atomic<Double>(0)
    private let ramp = Atomic<Double>(NoiseEngine.fadeInSeconds)
    private let volumeGain = Atomic<Double>(1)
    private let kindRaw: Atomic<Int>
    private let finished = Atomic<Bool>(false)

    // UI thread only.
    private var pausedRemaining: Double?
    private var engine: AVAudioEngine?
    private var configObserver: NSObjectProtocol?
    private var rebuildTimer: Timer?
    private var deviceListener: AudioObjectPropertyListenerBlock?

    // Render thread only.
    private var current = 0.0
    private var activeKind: NoiseKind?
    private var filters: [NoiseFilter]
    private var rng = GaussianNoise()
    private let norm: [Double]

    var state: PlayState {
        PlayState(rawValue: stateRaw.load(ordering: .relaxed)) ?? .idle
    }

    init(settings: Settings) {
        kindRaw = Atomic(settings.noise.rawValue)
        var measure = GaussianNoise()
        var norm: [Double] = []
        for kind in NoiseKind.allCases {
            var filter = NoiseEngine.makeFilter(kind)
            norm.append(NoiseEngine.measureNorm(filter: &filter, rng: &measure))
        }
        self.norm = norm
        filters = NoiseKind.allCases.map(NoiseEngine.makeFilter)
        setVolumeDb(settings.volumeDb)
        startEngine()
        watchDefaultOutput()
    }

    deinit {
        close()
    }

    // MARK: - Control (UI thread)

    func setNoise(_ kind: NoiseKind) {
        kindRaw.store(kind.rawValue, ordering: .relaxed)
    }

    func setVolumeDb(_ db: Double) {
        volumeGain.store(pow(10, db / 20), ordering: .relaxed)
    }

    /// Also restarts a running timer: the ramp simply continues from the current gain.
    func start(seconds: Double?) {
        deadline.store(seconds.map { monotonicNow() + $0 } ?? 0, ordering: .relaxed)
        stateRaw.store(PlayState.playing.rawValue, ordering: .relaxed)
        rampTo(1, seconds: Self.fadeInSeconds)
    }

    func pause() {
        guard state == .playing else { return }
        let dl = deadline.load(ordering: .relaxed)
        pausedRemaining = dl > 0 ? dl - monotonicNow() : nil
        stateRaw.store(PlayState.paused.rawValue, ordering: .relaxed)
        rampTo(0, seconds: Self.pauseFadeSeconds)
    }

    func resume() {
        guard state == .paused else { return }
        if let remaining = pausedRemaining {
            deadline.store(monotonicNow() + remaining, ordering: .relaxed)
        }
        stateRaw.store(PlayState.playing.rawValue, ordering: .relaxed)
        rampTo(1, seconds: Self.pauseFadeSeconds)
    }

    func remaining() -> Double? {
        switch state {
        case .playing:
            let dl = deadline.load(ordering: .relaxed)
            return dl > 0 ? max(0, dl - monotonicNow()) : nil
        case .paused:
            return pausedRemaining
        case .idle:
            return nil
        }
    }

    func takeFinished() -> Bool {
        finished.exchange(false, ordering: .relaxed)
    }

    func close() {
        rebuildTimer?.invalidate()
        rebuildTimer = nil
        if let observer = configObserver {
            NotificationCenter.default.removeObserver(observer)
            configObserver = nil
        }
        engine?.stop()
        engine = nil
    }

    private func rampTo(_ value: Double, seconds: Double) {
        ramp.store(seconds, ordering: .relaxed)
        target.store(value, ordering: .relaxed)
    }

    // MARK: - Audio graph

    private func startEngine() {
        let engine = AVAudioEngine()
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 1) else {
            return
        }
        let source = AVAudioSourceNode(format: format) { [unowned self] _, _, frameCount, bufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            guard let data = buffers[0].mData else { return noErr }
            render(frameCount: Int(frameCount), into: data.assumingMemoryBound(to: Float.self))
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            NSLog("noiser: audio engine failed to start: \(error)")
        }
        self.engine = engine
        // Device or format changes stop the engine; a fresh one picks up the new default output.
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            self?.scheduleRebuild()
        }
    }

    /// The engine follows the default output device, but only reports it through the
    /// configuration-change notification once the format actually differs. Listening to
    /// CoreAudio directly covers switches between devices with identical formats.
    private func watchDefaultOutput() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { self?.scheduleRebuild() }
        }
        deviceListener = listener
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
    }

    /// Device switches fire several notifications in a row; rebuild once they settle.
    private func scheduleRebuild() {
        rebuildTimer?.invalidate()
        rebuildTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            guard let self else { return }
            rebuildTimer = nil
            close()
            startEngine()
        }
    }

    // MARK: - Render thread

    private static func makeFilter(_ kind: NoiseKind) -> NoiseFilter {
        let lowCut = IIRFilter.butterworthHighPass(cutoff: lowCutHz, sampleRate: sampleRate)
        switch kind {
        case .white:
            return NoiseFilter(stages: [])
        case .pink:
            let pink = IIRFilter(
                b: [0.049922035, -0.095993537, 0.050612699, -0.004408786],
                a: [1.0, -2.494956002, 2.017265875, -0.522189400]
            )
            return NoiseFilter(stages: [pink, lowCut])
        case .brown:
            let brown = IIRFilter(b: [1], a: [1, -leak])
            return NoiseFilter(stages: [brown, lowCut])
        }
    }

    private static func measureNorm(filter: inout NoiseFilter, rng: inout GaussianNoise) -> Double {
        let total = Int(2 * sampleRate)
        let skip = Int(sampleRate / 2)  // the filter's settling transient
        var sum = 0.0
        for i in 0..<total {
            let y = filter.process(rng.next())
            if i >= skip { sum += y * y }
        }
        return targetRMS / sqrt(sum / Double(total - skip))
    }

    private func render(frameCount: Int, into out: UnsafeMutablePointer<Float>) {
        let kind = NoiseKind(rawValue: kindRaw.load(ordering: .relaxed)) ?? .white
        if kind != activeKind {
            activeKind = kind
            filters[kind.rawValue].reset()
        }

        // Linear ramp towards the target gain, at most `ramp` seconds for a full swing.
        let frames = Double(frameCount)
        let maxChange = frames / (ramp.load(ordering: .relaxed) * Self.sampleRate)
        let change = min(max(target.load(ordering: .relaxed) - current, -maxChange), maxChange)
        let start = current
        current = start + change

        var fadeRemaining: Double?
        if stateRaw.load(ordering: .relaxed) == PlayState.playing.rawValue {
            let dl = deadline.load(ordering: .relaxed)
            if dl > 0 {
                let remaining = dl - monotonicNow()
                if remaining <= 0 {
                    stateRaw.store(PlayState.idle.rawValue, ordering: .relaxed)
                    deadline.store(0, ordering: .relaxed)
                    target.store(0, ordering: .relaxed)
                    current = 0
                    finished.store(true, ordering: .relaxed)
                    out.update(repeating: 0, count: frameCount)
                    return
                }
                fadeRemaining = remaining
            }
        }

        let gain = norm[kind.rawValue] * volumeGain.load(ordering: .relaxed)
        for i in 0..<frameCount {
            var env = start + change * Double(i + 1) / frames
            if let remaining = fadeRemaining {
                let fade = (remaining - Double(i) / Self.sampleRate) / Self.fadeOutSeconds
                env *= min(max(fade, 0), 1)
            }
            let sample = filters[kind.rawValue].process(rng.next())
            out[i] = Float(tanh(sample * gain * env))
        }
    }
}

import Foundation
import AVFoundation
import AppKit

// MARK: - Chiptune Audio Engine
// Synthesized 8-bit sounds using AVAudioEngine — matches the web prototype's Web Audio API approach.
// No audio files needed. All sounds are generated programmatically.

final class ChiptuneEngine {
    static let shared = ChiptuneEngine()

    private let engine = AVAudioEngine()
    private let mixer = AVAudioMixerNode()
    private let sfxMixer = AVAudioMixerNode()
    private let musicMixer = AVAudioMixerNode()
    private let sampleRate: Double = 44100
    private var isRunning = false

    private init() {
        engine.attach(mixer)
        engine.attach(sfxMixer)
        engine.attach(musicMixer)

        engine.connect(sfxMixer, to: mixer, format: nil)
        engine.connect(musicMixer, to: mixer, format: nil)
        engine.connect(mixer, to: engine.mainMixerNode, format: nil)

        mixer.outputVolume = 0.35
        sfxMixer.outputVolume = 0.5
        musicMixer.outputVolume = 0.25
    }

    func start() {
        guard !isRunning else { return }
        do {
            engine.prepare()
            try engine.start()
            isRunning = true
            print("[ChiptuneEngine] Started successfully")
        } catch {
            print("[ChiptuneEngine] Start failed: \(error)")
            // Retry once after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self, !self.isRunning else { return }
                do {
                    self.engine.prepare()
                    try self.engine.start()
                    self.isRunning = true
                    print("[ChiptuneEngine] Retry succeeded")
                } catch {
                    print("[ChiptuneEngine] Retry also failed: \(error)")
                }
            }
        }
    }

    func stop() {
        engine.stop()
        isRunning = false
    }

    // MARK: - Note Frequency Helper

    private static let noteNames = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]

    static func freq(_ note: String) -> Double {
        // Parse note name like "C5", "G#4", etc.
        let name: String
        let octave: Int
        if note.count >= 2 {
            if note.contains("#") {
                name = String(note.prefix(2))
                octave = Int(String(note.suffix(1))) ?? 4
            } else {
                name = String(note.prefix(1))
                octave = Int(String(note.suffix(1))) ?? 4
            }
        } else {
            return 440.0
        }

        guard let index = noteNames.firstIndex(of: name) else { return 440.0 }
        let semitone = (octave - 4) * 12 + (index - 9)
        return 440.0 * pow(2.0, Double(semitone) / 12.0)
    }

    // MARK: - Waveform Generation

    enum WaveType {
        case square, triangle, sawtooth, sine, noise
    }

    /// Generate a buffer of a single waveform note
    private func generateBuffer(frequency: Double, duration: Double, waveType: WaveType, volume: Float = 0.3) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }

        buffer.frameLength = frameCount
        guard let data = buffer.floatChannelData?[0] else { return nil }

        let period = sampleRate / max(frequency, 1)

        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            let phase = Double(i).truncatingRemainder(dividingBy: period) / period
            // Envelope: quick attack, exponential decay
            let envelope = Float(max(0.001, exp(-3.0 * t / duration)))

            var sample: Float = 0

            switch waveType {
            case .square:
                sample = phase < 0.5 ? 1.0 : -1.0
            case .triangle:
                sample = phase < 0.5
                    ? Float(4.0 * phase - 1.0)
                    : Float(3.0 - 4.0 * phase)
            case .sawtooth:
                sample = Float(2.0 * phase - 1.0)
            case .sine:
                sample = Float(sin(2.0 * .pi * phase))
            case .noise:
                sample = Float.random(in: -1...1)
            }

            data[i] = sample * volume * envelope
        }

        return buffer
    }

    // MARK: - Play Note

    func playNote(frequency: Double, duration: Double, wave: WaveType = .square, volume: Float = 0.3, delay: Double = 0, toMixer: AVAudioMixerNode? = nil) {
        if !isRunning {
            // Try to restart engine if it stopped unexpectedly
            start()
            guard isRunning else { return }
        }
        guard let buffer = generateBuffer(frequency: frequency, duration: duration, waveType: wave, volume: volume) else { return }
        let format = buffer.format
        let target = toMixer ?? sfxMixer

        if delay > 0 {
            // Use DispatchQueue delay instead of AVAudioTime for reliable scheduling
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self, self.isRunning else { return }
                let playerNode = AVAudioPlayerNode()
                self.engine.attach(playerNode)
                self.engine.connect(playerNode, to: target, format: format)
                playerNode.scheduleBuffer(buffer) {
                    DispatchQueue.main.async { [weak self] in
                        self?.cleanupNode(playerNode)
                    }
                }
                playerNode.play()
            }
        } else {
            let playerNode = AVAudioPlayerNode()
            engine.attach(playerNode)
            engine.connect(playerNode, to: target, format: format)
            playerNode.scheduleBuffer(buffer) {
                DispatchQueue.main.async { [weak self] in
                    self?.cleanupNode(playerNode)
                }
            }
            playerNode.play()
        }
    }

    private func cleanupNode(_ node: AVAudioPlayerNode) {
        node.stop()
        engine.disconnectNodeOutput(node)
        engine.detach(node)
    }

    /// Convenience: play a named note like "C5"
    func playNote(_ note: String, duration: Double, wave: WaveType = .square, volume: Float = 0.3, delay: Double = 0, toMixer: AVAudioMixerNode? = nil) {
        playNote(frequency: Self.freq(note), duration: duration, wave: wave, volume: volume, delay: delay, toMixer: toMixer)
    }

    /// Play a noise burst (percussion)
    func playNoise(duration: Double, delay: Double = 0, volume: Float = 0.08) {
        playNote(frequency: 1000, duration: duration, wave: .noise, volume: volume, delay: delay)
    }

    // MARK: - Music-Specific Playback (routes to musicMixer)

    func playMusicNote(_ note: String, duration: Double, wave: WaveType = .square, volume: Float = 0.2, delay: Double = 0) {
        playNote(frequency: Self.freq(note), duration: duration, wave: wave, volume: volume, delay: delay, toMixer: musicMixer)
    }

    func playMusicNoise(duration: Double, delay: Double = 0, volume: Float = 0.04) {
        playNote(frequency: 1000, duration: duration, wave: .noise, volume: volume, delay: delay, toMixer: musicMixer)
    }
}

// MARK: - Sound Manager (Public API)

/// Plays chiptune sound effects and manages background music.
/// Direct port of the web prototype's ChipAudio engine.
final class SoundManager {
    static let shared = SoundManager()
    var isEnabled: Bool = true
    private var isMuted: Bool = false
    private let chip = ChiptuneEngine.shared
    private var musicTimer: Timer?
    private var currentPhase: String = ""

    private init() {}

    func initialize() {
        chip.start()
    }

    func toggleMute() -> Bool {
        isMuted.toggle()
        if isMuted { stopMusic() }
        return isMuted
    }

    // MARK: - Sound Effects (matching web prototype exactly)

    /// Pet action — warm ascending chirp: C5→E5→G5→C6
    func playPet() {
        guard isEnabled, !isMuted else { return }
        chip.playNote("C5", duration: 0.1, wave: .square, volume: 0.25)
        chip.playNote("E5", duration: 0.1, wave: .square, volume: 0.25, delay: 0.08)
        chip.playNote("G5", duration: 0.15, wave: .square, volume: 0.3, delay: 0.16)
        chip.playNote("C6", duration: 0.2, wave: .triangle, volume: 0.2, delay: 0.26)
    }

    /// Feed action — bubbly eating sound: G4→C5→E5→G5→E5→C5 + noise
    func playFeed() {
        guard isEnabled, !isMuted else { return }
        chip.playNote("G4", duration: 0.06, wave: .square, volume: 0.2)
        chip.playNote("C5", duration: 0.06, wave: .square, volume: 0.22, delay: 0.06)
        chip.playNote("E5", duration: 0.06, wave: .square, volume: 0.24, delay: 0.12)
        chip.playNote("G5", duration: 0.06, wave: .square, volume: 0.22, delay: 0.18)
        chip.playNote("E5", duration: 0.06, wave: .square, volume: 0.2, delay: 0.24)
        chip.playNote("C5", duration: 0.08, wave: .triangle, volume: 0.18, delay: 0.30)
        chip.playNoise(duration: 0.04, delay: 0.15, volume: 0.06)
    }

    /// Play action — excited ascending sweep whoosh
    func playPlay() {
        guard isEnabled, !isMuted else { return }
        let sweep = ["C4","D4","E4","F4","G4","A4","B4","C5","D5","E5","G5","C6"]
        for (i, note) in sweep.enumerated() {
            chip.playNote(note, duration: 0.06, wave: .sawtooth, volume: 0.12 + Float(i) * 0.015, delay: Double(i) * 0.035)
        }
        chip.playNoise(duration: 0.08, delay: 0.3, volume: 0.08)
    }

    /// Train action — studious page-flip: E4→G4→A4 + noise
    func playTrain() {
        guard isEnabled, !isMuted else { return }
        chip.playNote("E4", duration: 0.08, wave: .triangle, volume: 0.2)
        chip.playNote("G4", duration: 0.08, wave: .triangle, volume: 0.2, delay: 0.1)
        chip.playNote("A4", duration: 0.12, wave: .triangle, volume: 0.22, delay: 0.2)
        chip.playNoise(duration: 0.02, delay: 0.05, volume: 0.05)
    }

    /// Tab switch — quick blip: E5→A5
    func playTabSwitch() {
        guard isEnabled, !isMuted else { return }
        chip.playNote("E5", duration: 0.05, wave: .square, volume: 0.15)
        chip.playNote("A5", duration: 0.08, wave: .square, volume: 0.12, delay: 0.04)
    }

    /// Level up / achievement — triumphant fanfare: C5→E5→G5→C6+E6 + noise
    func playLevelUp() {
        guard isEnabled, !isMuted else { return }
        chip.playNote("C5", duration: 0.12, wave: .square, volume: 0.25)
        chip.playNote("E5", duration: 0.12, wave: .square, volume: 0.25, delay: 0.12)
        chip.playNote("G5", duration: 0.12, wave: .square, volume: 0.28, delay: 0.24)
        chip.playNote("C6", duration: 0.3, wave: .square, volume: 0.3, delay: 0.38)
        chip.playNote("E6", duration: 0.35, wave: .triangle, volume: 0.15, delay: 0.38)
        chip.playNoise(duration: 0.06, delay: 0.38, volume: 0.06)
    }

    /// Next step — gentle chime: C5→G5
    func playNextStep() {
        guard isEnabled, !isMuted else { return }
        chip.playNote("C5", duration: 0.08, wave: .triangle, volume: 0.2)
        chip.playNote("G5", duration: 0.12, wave: .triangle, volume: 0.18, delay: 0.1)
    }

    /// Character select — sparkly ascending: E5→G5→C6→E6
    func playCharSelect() {
        guard isEnabled, !isMuted else { return }
        chip.playNote("E5", duration: 0.08, wave: .square, volume: 0.2)
        chip.playNote("G5", duration: 0.08, wave: .square, volume: 0.22, delay: 0.07)
        chip.playNote("C6", duration: 0.08, wave: .square, volume: 0.25, delay: 0.14)
        chip.playNote("E6", duration: 0.15, wave: .triangle, volume: 0.18, delay: 0.22)
    }

    /// Splash appear — grand ascending entrance
    func playSplashIn() {
        guard isEnabled, !isMuted else { return }
        let notes = ["C4","E4","G4","C5","E5","G5","C6"]
        for (i, note) in notes.enumerated() {
            chip.playNote(note, duration: 0.12, wave: .square, volume: 0.12 + Float(i) * 0.02, delay: Double(i) * 0.08)
        }
        chip.playNote("C6", duration: 0.4, wave: .triangle, volume: 0.15, delay: 0.6)
    }

    /// XP gain — short pop chirp
    func playXPGain() {
        guard isEnabled, !isMuted else { return }
        chip.playNote("E5", duration: 0.06, wave: .square, volume: 0.18)
        chip.playNote("G5", duration: 0.08, wave: .triangle, volume: 0.15, delay: 0.05)
    }

    /// Success — warm completion chime
    func playSuccess() {
        guard isEnabled, !isMuted else { return }
        chip.playNote("C5", duration: 0.1, wave: .triangle, volume: 0.2)
        chip.playNote("E5", duration: 0.1, wave: .triangle, volume: 0.22, delay: 0.08)
        chip.playNote("G5", duration: 0.15, wave: .triangle, volume: 0.25, delay: 0.16)
    }

    /// Error / wrong answer — descending buzz
    func playError() {
        guard isEnabled, !isMuted else { return }
        chip.playNote("E4", duration: 0.1, wave: .square, volume: 0.2)
        chip.playNote("C4", duration: 0.15, wave: .square, volume: 0.22, delay: 0.1)
        chip.playNoise(duration: 0.04, delay: 0.05, volume: 0.06)
    }

    /// Streak milestone — ascending sparkle
    func playStreakMilestone() {
        guard isEnabled, !isMuted else { return }
        chip.playNote("G4", duration: 0.08, wave: .triangle, volume: 0.18)
        chip.playNote("C5", duration: 0.08, wave: .triangle, volume: 0.2, delay: 0.07)
        chip.playNote("E5", duration: 0.1, wave: .triangle, volume: 0.22, delay: 0.14)
        chip.playNote("G5", duration: 0.15, wave: .square, volume: 0.18, delay: 0.22)
    }

    /// Notification ping
    func playNotification() {
        guard isEnabled, !isMuted else { return }
        chip.playNote("A5", duration: 0.08, wave: .triangle, volume: 0.15)
        chip.playNote("E5", duration: 0.1, wave: .triangle, volume: 0.12, delay: 0.1)
    }

    /// Tap / click
    func playTap() {
        guard isEnabled, !isMuted else { return }
        chip.playNote("A5", duration: 0.03, wave: .square, volume: 0.12)
    }

    // MARK: - Background Music

    /// Start looping background music for a given phase
    func startMusic(_ phase: String = "home") {
        guard isEnabled, !isMuted else { return }
        guard phase != currentPhase else { return }
        stopMusic()
        currentPhase = phase
        loopMelody()
    }

    func stopMusic() {
        musicTimer?.invalidate()
        musicTimer = nil
        currentPhase = ""
    }

    func setPhase(_ phase: String) {
        if phase != currentPhase {
            startMusic(phase)
        }
    }

    private struct Melody {
        let notes: [String]
        let bass: [String]
        let tempo: Double  // BPM
        let wave: ChiptuneEngine.WaveType
        let bassWave: ChiptuneEngine.WaveType
    }

    private let melodies: [String: Melody] = [
        "splash": Melody(
            notes: ["C5","E5","G5","A5","G5","E5","C5","D5","E5","G5","A5","G5","E5","C5","D5","E5","G5","A5","G5","E5","C5","-","C5","E5"],
            bass:  ["C3","-","-","C3","-","-","A2","-","-","A2","-","-","F3","-","-","F3","-","-","G3","-","-","-","G3","-"],
            tempo: 220, wave: .square, bassWave: .triangle
        ),
        "onboarding": Melody(
            notes: ["E4","G4","A4","-","A4","G4","E4","D4","E4","-","G4","A4","C5","A4","G4","-","E4","D4","C4","-","-","-","C4","E4"],
            bass:  ["C3","-","-","-","C3","-","A2","-","-","-","A2","-","F2","-","-","-","F2","-","G2","-","-","-","G2","-"],
            tempo: 140, wave: .triangle, bassWave: .sine
        ),
        "home": Melody(
            notes: ["C4","E4","G4","C5","-","A4","G4","E4","D4","-","E4","G4","A4","G4","E4","C4","-","D4","E4","-","-","-","C4","E4"],
            bass:  ["C3","-","-","C3","-","-","A2","-","-","-","A2","-","F2","-","-","F2","-","-","G2","-","-","-","G2","-"],
            tempo: 160, wave: .square, bassWave: .triangle
        )
    ]

    private func loopMelody() {
        guard let m = melodies[currentPhase] else { return }
        let step = 60.0 / m.tempo

        // Lead melody (routes to musicMixer)
        for (i, note) in m.notes.enumerated() {
            guard note != "-" else { continue }
            chip.playMusicNote(note, duration: step * 1.5, wave: m.wave, volume: 0.2, delay: Double(i) * step)
        }

        // Bass line (routes to musicMixer)
        for (i, note) in m.bass.enumerated() {
            guard note != "-" else { continue }
            chip.playMusicNote(note, duration: step * 2.5, wave: m.bassWave, volume: 0.15, delay: Double(i) * step)
        }

        // Light percussion every 3rd beat (routes to musicMixer)
        for i in stride(from: 0, to: m.notes.count, by: 3) {
            chip.playMusicNoise(duration: 0.03, delay: Double(i) * step, volume: 0.04)
        }

        // Loop after melody completes
        let totalDuration = Double(m.notes.count) * step
        musicTimer = Timer.scheduledTimer(withTimeInterval: totalDuration, repeats: false) { [weak self] _ in
            self?.loopMelody()
        }
    }

    // MARK: - Legacy compatibility aliases

    /// Generic play by name (matches web's ChipAudio.play("name"))
    func play(_ name: String) {
        switch name {
        case "pet": playPet()
        case "feed": playFeed()
        case "play": playPlay()
        case "train": playTrain()
        case "tabSwitch": playTabSwitch()
        case "levelUp": playLevelUp()
        case "nextStep": playNextStep()
        case "charSelect": playCharSelect()
        case "splashIn": playSplashIn()
        case "success": playSuccess()
        case "error": playError()
        case "xp": playXPGain()
        case "streak": playStreakMilestone()
        case "notification": playNotification()
        case "tap": playTap()
        default: playTap()
        }
    }
}

import AppKit
import AVFoundation

/// A short, soft "detent" click plus a trackpad haptic, played on every dial step.
/// The click is synthesized once and scheduled on an audio engine so fast steps don't drop.
final class TickFeedback {
    static let shared = TickFeedback()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let buffer: AVAudioPCMBuffer?

    private init() {
        let sampleRate = 44_100.0
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let frames = AVAudioFrameCount(sampleRate * 0.015)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)
        if let buffer, let samples = buffer.floatChannelData?[0] {
            buffer.frameLength = frames
            for i in 0..<Int(frames) {
                let t = Double(i) / sampleRate
                let envelope = exp(-t * 520)
                let tone = sin(2 * .pi * 1_900 * t) * 0.7 + sin(2 * .pi * 3_100 * t) * 0.3
                samples[i] = Float(tone * envelope * 0.22)
            }
        }
        self.buffer = buffer
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    func tick() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        guard let buffer else { return }
        if !engine.isRunning {
            do { try engine.start() } catch { return }
        }
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !player.isPlaying { player.play() }
    }

    /// Release the audio device when the dial is not in use.
    func stop() {
        player.stop()
        engine.stop()
    }
}

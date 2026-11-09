import Foundation
import AudioToolbox
import AVFoundation
import os.lock

struct PulseDJFXSnapshot {
    var bass: Float = 1
    var filter: Float = 0
    var echo: Float = 0
    var active: Bool { abs(bass - 1) > 0.001 || filter > 0.001 || echo > 0.001 }
}
final class PulseDJFXParameters {
    private let lock = OSAllocatedUnfairLock(initialState: PulseDJFXSnapshot())
    func update(_ value: PulseDJFXSnapshot) { lock.withLock { $0 = value } }
    func read() -> PulseDJFXSnapshot? { lock.withLockIfAvailable { $0 } }
    static func values(effect: PulseDJTransition, progress: Double, incoming: Bool) -> PulseDJFXSnapshot {
        let p = Float(min(1, max(0, progress)))
        switch effect {
        case .blend: return PulseDJFXSnapshot()
        case .bassSwap: return PulseDJFXSnapshot(bass: incoming ? min(1, p * 2) : max(0, 1 - p * 2))
        case .echo: return incoming ? PulseDJFXSnapshot() : PulseDJFXSnapshot(bass: 1 - p * 0.7, filter: p * 0.45, echo: sin(p * .pi) * 0.42)
        case .filter: return PulseDJFXSnapshot(bass: incoming ? 0.35 + p * 0.65 : 1 - p * 0.5, filter: incoming ? 1 - p : p)
        }
    }
}

// Each AVPlayerItem owns its effect state so the incoming and outgoing tracks
// can hand off bass independently. All delay memory is allocated in prepare().
final class PulseDJFXKernel {
    let parameters: PulseDJFXParameters
    private var snapshot = PulseDJFXSnapshot()
    private var bassState: [Float] = [], filterState: [Float] = [], positions: [Int] = [], written: [Int] = []
    private var delay: [Float] = []
    private var delayFrames = 1, channels = 0
    private var bassAlpha: Float = 0, filterAlpha: Float = 0
    private var wasActive = false
    init(parameters: PulseDJFXParameters) { self.parameters = parameters }
    func prepare(rate: Double, channels: Int) {
        let rate = rate.isFinite && rate > 0 ? rate : 48000
        self.channels = max(1, min(8, channels))
        delayFrames = max(1, Int(min(192000, rate) * 0.375))
        delay = Array(repeating: 0, count: delayFrames * self.channels)
        bassState = Array(repeating: 0, count: self.channels); filterState = bassState
        positions = Array(repeating: 0, count: self.channels)
        written = positions; wasActive = false
        bassAlpha = Float(1 - exp(-2 * Double.pi * 180 / max(1, rate)))
        filterAlpha = Float(1 - exp(-2 * Double.pi * 1400 / max(1, rate)))
    }
    func process(_ buffers: UnsafeMutablePointer<AudioBufferList>, frames: Int) {
        if let next = parameters.read() { snapshot = next }
        guard channels > 0 else { return }
        guard snapshot.active else {
            if wasActive {
                for c in 0..<channels { written[c] = 0; positions[c] = 0; bassState[c] = 0; filterState[c] = 0 }
                wasActive = false
            }
            return
        }
        wasActive = true
        var base = 0
        for buffer in UnsafeMutableAudioBufferListPointer(buffers) {
            let stride = Int(buffer.mNumberChannels)
            guard stride > 0, let raw = buffer.mData else { continue }
            let samples = raw.assumingMemoryBound(to: Float.self)
            let count = min(frames, Int(buffer.mDataByteSize) / 4 / stride)
            for frame in 0..<count {
                for channel in 0..<stride where base + channel < channels {
                    let c = base + channel, index = frame * stride + channel
                    let raw = samples[index], original = raw.isFinite ? raw : 0
                    bassState[c] += bassAlpha * (original - bassState[c])
                    var x = original + bassState[c] * (snapshot.bass - 1)
                    filterState[c] += filterAlpha * (x - filterState[c])
                    x = x * (1 - snapshot.filter) + filterState[c] * snapshot.filter
                    let address = c * delayFrames + positions[c]
                    let delayed = written[c] >= delayFrames ? delay[address] : 0
                    delay[address] = x + delayed * 0.25
                    positions[c] = (positions[c] + 1) % delayFrames
                    written[c] = min(delayFrames, written[c] + 1)
                    x += delayed * snapshot.echo
                    samples[index] = min(1, max(-1, x))
                }
            }
            base += stride
        }
    }
}

import SwiftUI
import AVFoundation
import MediaToolbox
import AudioToolbox
import os.lock

struct PulseEQConfiguration: Codable, Equatable {
    var enabled = false
    var gains: [Float] = Array(repeating: 0, count: 10)
    var preset = "neutral"
    static let frequencies: [Double] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    var safeGains: [Float] { (0..<10).map { i in i < gains.count && gains[i].isFinite ? min(9, max(-9, gains[i])) : 0 } }
    var headroomDB: Float { -max(0, safeGains.max() ?? 0) }
}
struct PulseEQPreset: Identifiable {
    let id: String
    let name: String
    let detail: String
    let gains: [Float]
    static let all: [PulseEQPreset] = [
        .init(id: "neutral", name: "Нейтральный", detail: "Без изменения баланса", gains: [0,0,0,0,0,0,0,0,0,0]),
        .init(id: "bass", name: "Глубокий бас", detail: "Плотный низ без лишней резкости", gains: [5,4,3,1,0,0,0,1,1,0]),
        .init(id: "vocal", name: "Чистый вокал", detail: "Голос впереди, меньше гула", gains: [-2,-1,-1,-2,0,2,3,2,1,0]),
        .init(id: "warm", name: "Тёплый", detail: "Мягкий звук для долгого прослушивания", gains: [2,2,1,1,0,0,-1,-1,-2,-2]),
        .init(id: "rock", name: "Рок", detail: "Энергичные ударные и гитары", gains: [3,2,1,-1,-1,1,2,3,2,1]),
        .init(id: "electronic", name: "Электроника", detail: "Упругий бас и воздушный верх", gains: [4,3,1,0,-1,0,1,2,3,2]),
        .init(id: "acoustic", name: "Акустика", detail: "Разборчивые инструменты и детали", gains: [0,0,-1,0,1,2,2,1,2,1]),
        .init(id: "night", name: "Тихое прослушивание", detail: "Чуть больше краёв на низкой громкости", gains: [3,2,1,0,0,1,1,1,2,1])
    ]
}
@MainActor
final class PulseEqualizerSettings: ObservableObject {
    @Published private(set) var config: PulseEQConfiguration
    private var saving: Task<Void, Never>?
    init() {
        if let data = UserDefaults.standard.data(forKey: "pulse_native_equalizer"), let value = try? JSONDecoder().decode(PulseEQConfiguration.self, from: data) {
            var normalized = value; normalized.gains = value.safeGains; config = normalized
        } else { config = PulseEQConfiguration() }
    }
    func setEnabled(_ enabled: Bool) { var next = config; next.enabled = enabled; update(next) }
    func select(_ preset: PulseEQPreset) { update(PulseEQConfiguration(enabled: true, gains: preset.gains, preset: preset.id)) }
    func band(_ index: Int, gain: Float) { guard config.gains.indices.contains(index) else { return }; var next = config; next.gains[index] = min(9, max(-9, gain)); next.preset = "custom"; update(next) }
    func reset() { update(PulseEQConfiguration(enabled: config.enabled)) }
    private func update(_ value: PulseEQConfiguration) {
        config = value
        saving?.cancel()
        saving = Task { [value] in
            do { try await Task.sleep(nanoseconds: 200_000_000) } catch { return }
            if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: "pulse_native_equalizer") }
        }
    }
}

struct PulseEQSnapshot {
    var enabled = false
    var gains = SIMD16<Float>(repeating: 0)
    var preamp: Float = 1
    var revision: UInt64 = 0
}
// The render callback never waits for UI writes: if the short try-lock fails,
// it uses its previous fixed-size snapshot. No heap allocations in process().
final class PulseEQParameters {
    private let lock = OSAllocatedUnfairLock(initialState: PulseEQSnapshot())
    private let activity = OSAllocatedUnfairLock(initialState: UInt64(0))
    private let meter = OSAllocatedUnfairLock(initialState: Float(0))
    func recordLevel(_ value: Float) { _ = meter.withLockIfAvailable { $0 = value.isFinite ? value : 0 } }
    var level: Float { meter.withLock { $0 } }
    func update(_ config: PulseEQConfiguration) {
        let gains = config.safeGains
        lock.withLock { value in
            value.enabled = config.enabled && gains.contains { abs($0) > 0.001 }
            for i in 0..<10 { value.gains[i] = gains[i] }
            value.preamp = pow(10, config.headroomDB / 20)
            value.revision &+= 1
        }
    }
    func read() -> PulseEQSnapshot? { lock.withLockIfAvailable { $0 } }
    func record(frames: Int) { _ = activity.withLockIfAvailable { $0 &+= UInt64(max(0, frames)) } }
    func resetActivity() { activity.withLock { $0 = 0 } }
    var processedFrames: UInt64 { activity.withLock { $0 } }
}
final class PulseEQKernel {
    struct Coefficients { var b0 = 1.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0 }
    struct State { var z1 = 0.0, z2 = 0.0 }
    let parameters: PulseEQParameters
    private let effects: PulseDJFXKernel
    private var coefficients = Array(repeating: Coefficients(), count: 10)
    private var states: [State] = []
    private var channels = 0
    private var sampleRate = 48000.0
    private var supported = false
    private var snapshot = PulseEQSnapshot()
    private var revision = UInt64.max
    private var lowPass: Float = 0
    init(parameters: PulseEQParameters, effects: PulseDJFXParameters = PulseDJFXParameters()) { self.parameters = parameters; self.effects = PulseDJFXKernel(parameters: effects) }
    func prepare(_ format: AudioStreamBasicDescription) {
        channels = Int(format.mChannelsPerFrame); sampleRate = format.mSampleRate
        supported = format.mFormatID == kAudioFormatLinearPCM && format.mFormatFlags & kAudioFormatFlagIsFloat != 0 && format.mBitsPerChannel == 32 && channels > 0 && channels <= 8 && sampleRate > 0
        states = Array(repeating: State(), count: max(1, min(8, channels)) * 10)
        effects.prepare(rate: sampleRate, channels: channels)
        revision = UInt64.max
        _ = PulseEQConfiguration.frequencies.count
    }
    static func peak(frequency: Double, gain: Float, sampleRate: Double) -> Coefficients {
        let a = pow(10.0, Double(gain) / 40), omega = 2 * Double.pi * min(frequency, sampleRate * 0.45) / sampleRate
        let alpha = sin(omega) / 2, a0 = 1 + alpha / a
        return Coefficients(b0: (1 + alpha * a) / a0, b1: -2 * cos(omega) / a0, b2: (1 - alpha * a) / a0, a1: -2 * cos(omega) / a0, a2: (1 - alpha / a) / a0)
    }
    func process(_ buffers: UnsafeMutablePointer<AudioBufferList>, frames: Int) {
        guard supported else { return }
        if let next = parameters.read(), next.revision != revision {
            snapshot = next; revision = next.revision
            for band in 0..<10 { coefficients[band] = Self.peak(frequency: PulseEQConfiguration.frequencies[band], gain: next.gains[band], sampleRate: sampleRate) }
        }
        let list = UnsafeMutableAudioBufferListPointer(buffers)
        // A decimated bass envelope drives the vinyl even with EQ bypassed.
        // It reads PCM without changing the samples or downloading a second file.
        if let buffer = list.first, buffer.mNumberChannels > 0, let raw = buffer.mData {
            let stride = Int(buffer.mNumberChannels)
            let count = min(frames, Int(buffer.mDataByteSize) / 4 / stride)
            let samples = raw.assumingMemoryBound(to: Float.self)
            let alpha = Float(min(1, 2 * Double.pi * 180 / (sampleRate / 4)))
            var sum: Float = 0; var measured = 0
            for frame in Swift.stride(from: 0, to: count, by: 4) {
                let sample = samples[frame * stride]
                lowPass += alpha * ((sample.isFinite ? sample : 0) - lowPass)
                sum += lowPass * lowPass; measured += 1
            }
            parameters.recordLevel(measured > 0 ? sqrt(sum / Float(measured)) : 0)
        }
        guard snapshot.enabled else { effects.process(buffers, frames: frames); return }
        var channelBase = 0
        for buffer in list {
            let stride = Int(buffer.mNumberChannels)
            guard stride > 0, let raw = buffer.mData else { continue }
            let samples = raw.assumingMemoryBound(to: Float.self)
            let count = min(frames, Int(buffer.mDataByteSize) / MemoryLayout<Float>.size / stride)
            for frame in 0..<count {
                for channel in 0..<stride where channelBase + channel < channels {
                    var x = Double(samples[frame * stride + channel]) * Double(snapshot.preamp)
                    let base = (channelBase + channel) * 10
                    for band in 0..<10 {
                        let c = coefficients[band], index = base + band
                        let y = c.b0 * x + states[index].z1
                        states[index].z1 = c.b1 * x - c.a1 * y + states[index].z2
                        states[index].z2 = c.b2 * x - c.a2 * y
                        x = y
                    }
                    samples[frame * stride + channel] = x.isFinite ? Float(min(1, max(-1, x))) : 0
                }
            }
            channelBase += stride
        }
        parameters.record(frames: frames)
        effects.process(buffers, frames: frames)
    }
    static func makeTap(parameters: PulseEQParameters, effects: PulseDJFXParameters = PulseDJFXParameters()) -> MTAudioProcessingTap? {
        let pointer = Unmanaged.passRetained(PulseEQKernel(parameters: parameters, effects: effects)).toOpaque()
        var callbacks = MTAudioProcessingTapCallbacks(version: kMTAudioProcessingTapCallbacksVersion_0, clientInfo: pointer,
            init: { _, info, storage in storage.pointee = info },
            finalize: { tap in Unmanaged<PulseEQKernel>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release() },
            prepare: { tap, _, format in Unmanaged<PulseEQKernel>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue().prepare(format.pointee) },
            unprepare: { _ in },
            process: { tap, frames, _, buffers, framesOut, flagsOut in
                let status = MTAudioProcessingTapGetSourceAudio(tap, frames, buffers, flagsOut, nil, framesOut)
                guard status == noErr, framesOut.pointee > 0 else { return }
                Unmanaged<PulseEQKernel>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue().process(buffers, frames: Int(framesOut.pointee))
            })
        #if compiler(>=6.2)
        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &tap)
        guard status == noErr, let tap else { Unmanaged<PulseEQKernel>.fromOpaque(pointer).release(); return nil }
        return tap
        #else
        var tap: Unmanaged<MTAudioProcessingTap>?
        let status = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &tap)
        guard status == noErr, let tap else { Unmanaged<PulseEQKernel>.fromOpaque(pointer).release(); return nil }
        return tap.takeRetainedValue()
        #endif
    }
}
final class PulseEQController {
    private struct EffectEntry { weak var item: AVPlayerItem?; let parameters: PulseDJFXParameters }
    private var effects: [ObjectIdentifier: EffectEntry] = [:]
    private let parameters = PulseEQParameters()
    private var enabled = false
    private var installing = Set<ObjectIdentifier>()
    var onError: ((String) -> Void)?
    var hasProcessedAudio: Bool { enabled && parameters.processedFrames > 0 }
    var bassLevel: Double { min(1, Double(parameters.level) / 0.16) }
    func configure(_ value: PulseEQConfiguration) { parameters.update(value); parameters.resetActivity(); enabled = value.enabled }
    func transition(item: AVPlayerItem?, value: PulseDJFXSnapshot) {
        guard let item else { return }
        effects[ObjectIdentifier(item)]?.parameters.update(value)
    }
    func resetTransition() {
        effects = effects.filter { $0.value.item != nil }
        for entry in effects.values { entry.parameters.update(PulseDJFXSnapshot()) }
    }
    func attach(to item: AVPlayerItem?) {
        guard let item, item.audioMix == nil else { return }
        let identity = ObjectIdentifier(item)
        guard installing.insert(identity).inserted else { return }
        effects = effects.filter { $0.value.item != nil }
        let effectParameters = PulseDJFXParameters()
        effects[identity] = EffectEntry(item: item, parameters: effectParameters)
        Task { @MainActor [weak self, weak item] in
            guard let self else { return }
            defer { self.installing.remove(identity) }
            guard let item else { return }
            do {
                let tracks = try await item.asset.loadTracks(withMediaType: .audio)
                guard let track = tracks.first, let tap = PulseEQKernel.makeTap(parameters: self.parameters, effects: effectParameters) else { if self.enabled { self.onError?("Для этого трека эквалайзер недоступен") }; return }
                let input = AVMutableAudioMixInputParameters(track: track)
                input.audioTapProcessor = tap
                let mix = AVMutableAudioMix(); mix.inputParameters = [input]; item.audioMix = mix
            } catch { if self.enabled { self.onError?("Не удалось подключить эквалайзер к треку") } }
        }
    }
}

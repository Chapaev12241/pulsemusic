import XCTest
import AudioToolbox
import MediaPlayer
import AVFoundation
#if os(iOS)
@testable import Pulse
#else
@testable import PulseMac
#endif

final class PulseDJAndWordsTests: XCTestCase {
    func testVinylMeterReadsBassWithoutEnablingOrChangingEQ() {
        let parameters = PulseEQParameters()
        let meterKernel = PulseEQKernel(parameters: parameters)
        meterKernel.prepare(AudioStreamBasicDescription(mSampleRate: 48000, mFormatID: kAudioFormatLinearPCM, mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked, mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: 1, mBitsPerChannel: 32, mReserved: 0))
        var samples = (0..<4800).map { Float(sin(2 * Double.pi * 64 * Double($0) / 48000) * 0.3) }
        let original = samples
        samples.withUnsafeMutableBufferPointer { memory in
            var list = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(memory.count * 4), mData: memory.baseAddress))
            withUnsafeMutablePointer(to: &list) { meterKernel.process($0, frames: memory.count) }
        }
        XCTAssertEqual(samples, original)
        XCTAssertGreaterThan(parameters.level, 0.15)
        XCTAssertEqual(parameters.processedFrames, 0)
    }
    func testEnhancedWordsPreserveOffsetsRepeatedLinesAndEndMarks() {
        let lines = PulseLRC.parse("[offset:-200]\n[00:10.00][00:20.00]<00:10.00>Привет <00:10.50>мир<00:11.40>\n[00:30]Конец")
        XCTAssertEqual(lines.map(\.text), ["Привет мир", "Привет мир", "Конец"])
        let first = PulseLRC.words(for: lines[0], next: lines[1].time, duration: 40)
        let repeatWords = PulseLRC.words(for: lines[1], next: lines[2].time, duration: 40)
        XCTAssertEqual(first.map(\.text), ["Привет", "мир"])
        XCTAssertEqual(first[0].start, 9.8, accuracy: 0.001)
        XCTAssertEqual(first[1].end, 11.2, accuracy: 0.001)
        XCTAssertEqual(repeatWords[0].start, 19.8, accuracy: 0.001)
        XCTAssertEqual(repeatWords[1].end, 21.2, accuracy: 0.001)
    }
    func testEstimatedWordsStayInsideShortLineAndHandlePunctuation() {
        let line = PulseLyricLine(id: 0, time: 1, text: "Ты — моя музыка!")
        let words = PulseLRC.words(for: line, next: 2, duration: 200)
        XCTAssertEqual(words.map(\.text).joined(separator: " "), line.text)
        XCTAssertEqual(words.first?.start, 1)
        XCTAssertEqual(words.last?.end ?? 0, 2, accuracy: 0.001)
        XCTAssertTrue(words.allSatisfy { $0.end > $0.start })
    }
    func testSearchMatchesArtistAccentsSpacingAndEveryQueryToken() {
        XCTAssertTrue(PulseSearch.matches("Алёна Швец. — Любимая песня", query: "  алена   песня "))
        XCTAssertTrue(PulseSearch.matches("MORGENSHTERN", query: "morgen"))
        XCTAssertFalse(PulseSearch.matches("Nirvana School", query: "Nirvana Blew"))
    }
    func testTempoDetectorFindsSynthetic120BPMAndRejectsSilence() {
        let envelope = (0..<2500).map { $0 % 25 == 0 ? 1.0 : 0.0 }
        let feature = PulseDJAnalyzer.features(id: "beat", envelope: envelope, envelopeRate: 50, rms: 0.1, bassRatio: 0.5, crossingRate: 0.1)
        XCTAssertEqual(feature.bpm ?? 0, 120, accuracy: 1)
        XCTAssertGreaterThan(feature.confidence, 0.5)
        let silence = PulseDJAnalyzer.features(id: "silence", envelope: Array(repeating: 0, count: 500), envelopeRate: 50, rms: 0, bassRatio: 0, crossingRate: 0)
        XCTAssertNil(silence.bpm)
        XCTAssertEqual(silence.energy, 0)
    }
    func testStreamingAnalyzerDecodesDownloadedFileWithoutExtension() throws {
        let wave = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        let downloaded = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".tmp")
        defer { try? FileManager.default.removeItem(at: wave); try? FileManager.default.removeItem(at: downloaded) }
        let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16000 * 12)!
        buffer.frameLength = buffer.frameCapacity
        let samples = buffer.floatChannelData![0]
        for i in 0..<Int(buffer.frameLength) {
            let time = Double(i) / 16000
            samples[i] = time.truncatingRemainder(dividingBy: 0.5) < 0.08 ? Float(sin(2 * .pi * 100 * time) * 0.3) : 0
        }
        do { let file = try AVAudioFile(forWriting: wave, settings: format.settings); try file.write(from: buffer) }
        try FileManager.default.moveItem(at: wave, to: downloaded)
        let result = try PulseDJAnalyzer.decode(id: "downloaded", url: downloaded)
        XCTAssertEqual(result.bpm ?? 0, 120, accuracy: 5)
        XCTAssertGreaterThan(result.bass, 0.3)
        XCTAssertTrue(result.energy.isFinite)
    }
    func testDJOrdersCompatibleSoundBeforeClashingTempoAndPreservesEveryTrack() {
        let a = PulseDJFeatures(id: "seed", bpm: 120, confidence: 0.8, energy: 0.6, brightness: 0.4, bass: 0.6)
        let b = PulseDJFeatures(id: "near", bpm: 122, confidence: 0.8, energy: 0.58, brightness: 0.42, bass: 0.55)
        let c = PulseDJFeatures(id: "far", bpm: 90, confidence: 0.8, energy: 0.1, brightness: 0.9, bass: 0.1)
        XCTAssertEqual(PulseDJMatcher.order([c,b,a], seed: a.id).map(\.id), ["seed","near","far"])
        XCTAssertEqual(PulseDJMatcher.tempoDistance(80, 160), 0, accuracy: 0.001)
        XCTAssertEqual(PulseDJMatcher.transition(from: a, to: b, index: 0).effect, .bassSwap)
    }
    func testDJEffectsBypassExactlyAndBassHandoffChangesAudio() {
        func render(_ value: PulseDJFXSnapshot) -> [Float] {
            let parameters = PulseDJFXParameters(); parameters.update(value)
            let kernel = PulseDJFXKernel(parameters: parameters); kernel.prepare(rate: 48000, channels: 1)
            var samples = (0..<4800).map { Float(sin(2 * Double.pi * 64 * Double($0) / 48000) * 0.2) }
            samples.withUnsafeMutableBufferPointer { memory in
                var list = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(memory.count * 4), mData: memory.baseAddress))
                withUnsafeMutablePointer(to: &list) { kernel.process($0, frames: memory.count) }
            }
            return samples
        }
        let flat = render(PulseDJFXSnapshot()), cut = render(PulseDJFXSnapshot(bass: 0))
        XCTAssertEqual(flat, (0..<4800).map { Float(sin(2 * Double.pi * 64 * Double($0) / 48000) * 0.2) })
        XCTAssertLessThan(cut.dropFirst(1000).reduce(0) { $0 + $1 * $1 }, flat.dropFirst(1000).reduce(0) { $0 + $1 * $1 } * 0.25)
        for effect in PulseDJTransition.allCases {
            let values = render(PulseDJFXParameters.values(effect: effect, progress: 0.5, incoming: false))
            XCTAssertTrue(values.allSatisfy { $0.isFinite && abs($0) <= 1 })
        }
    }
    @MainActor
    func testSystemFavoriteUsesCurrentTrackAndRejectsLoggedOutState() async {
        let player = NativePlayer(); var received: [String] = []
        player.onFavorite = { received.append($0) }
        player.setFavoriteState(trackID: "first", available: true, liked: false)
        XCTAssertEqual(player.toggleFavoriteFromSystem(), .success)
        player.setFavoriteState(trackID: "second", available: true, liked: true)
        XCTAssertTrue(MPRemoteCommandCenter.shared().likeCommand.isActive)
        XCTAssertEqual(player.toggleFavoriteFromSystem(), .success)
        player.setFavoriteState(trackID: "second", available: false, liked: false)
        XCTAssertEqual(player.toggleFavoriteFromSystem(), .noSuchContent)
        XCTAssertEqual(received, ["first", "second"])
    }
    func testEchoDoesNotReplayOldSamplesAfterEffectReset() {
        let parameters = PulseDJFXParameters()
        let activeKernel = PulseDJFXKernel(parameters: parameters)
        activeKernel.prepare(rate: 48000, channels: 1)
        func process(_ value: Float, count: Int) -> [Float] {
            var samples = Array(repeating: value, count: count)
            samples.withUnsafeMutableBufferPointer { memory in
                var list = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(memory.count * 4), mData: memory.baseAddress))
                withUnsafeMutablePointer(to: &list) { activeKernel.process($0, frames: memory.count) }
            }
            return samples
        }
        parameters.update(PulseDJFXSnapshot(echo: 0.4)); _ = process(0.2, count: 24000)
        parameters.update(PulseDJFXSnapshot()); _ = process(0, count: 512)
        parameters.update(PulseDJFXSnapshot(echo: 0.4))
        XCTAssertTrue(process(0, count: 24000).allSatisfy { abs($0) < 0.00001 })
    }
}

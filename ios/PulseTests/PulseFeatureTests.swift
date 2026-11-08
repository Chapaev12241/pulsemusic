import XCTest
import AVFoundation
import AudioToolbox
#if os(iOS)
@testable import Pulse
#else
@testable import PulseMac
#endif

final class PulseLyricsAndGestureTests: XCTestCase {
    func testLRCOffsetsAndRepeatedTimestamps() {
        let lines = PulseLRC.parse("[offset:-500]\n[00:01.50][00:03.00]Hello\n[00:05.00]World")
        XCTAssertEqual(lines.map(\.time), [1,2.5,4.5])
        XCTAssertEqual(lines.map(\.text), ["Hello","Hello","World"])
        XCTAssertNil(PulseLRC.activeIndex(at: 0, lines: lines))
        XCTAssertEqual(PulseLRC.activeIndex(at: 2.6, lines: lines), 1)
        XCTAssertEqual(PulseLRC.activeIndex(at: 100, lines: lines), 2)
    }
    func testSwipeRejectsVerticalScrollAndShortDrags() {
        XCTAssertEqual(PulseTrackSwipe.direction(horizontal: -100, vertical: 10), 1)
        XCTAssertEqual(PulseTrackSwipe.direction(horizontal: 100, vertical: -15), -1)
        XCTAssertNil(PulseTrackSwipe.direction(horizontal: 20, vertical: 1))
        XCTAssertNil(PulseTrackSwipe.direction(horizontal: 80, vertical: 90))
    }
    func testInviteAcceptsLinkAndIDButNotMalformedProfile() {
        let id = "0c78cf47-44f2-4343-9575-d45be259ec61"
        XCTAssertEqual(PulseSocialStore.friendID(from: "https://example.invalid/?friend=" + id), id)
        XCTAssertEqual(PulseSocialStore.friendID(from: id.uppercased()), id)
        XCTAssertNil(PulseSocialStore.friendID(from: "someone@example.com"))
    }
    @MainActor
    func testChatMergeDeduplicatesAndPreservesServerOrder() async throws {
        let data = Data(#"{"messages":[{"id":2,"sender":"a","recipient":"b","body":"Two","created_at":"2026-11-09T01:00:00Z"},{"id":1,"sender":"b","recipient":"a","body":"One","created_at":"2026-11-09T00:00:00Z"}],"hasMore":false}"#.utf8)
        let page = try JSONDecoder().decode(PulseMessages.self, from: data)
        let merged = PulseChatStore.merge(page.messages, page.messages)
        XCTAssertEqual(merged.map(\.id), [1,2])
    }
}
final class PulseEqualizerTests: XCTestCase {
    private func render(frequency: Double, config: PulseEQConfiguration) -> [Float] {
        let parameters = PulseEQParameters(); parameters.update(config)
        let kernel = PulseEQKernel(parameters: parameters)
        let format = AudioStreamBasicDescription(mSampleRate: 48000, mFormatID: kAudioFormatLinearPCM, mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked, mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: 1, mBitsPerChannel: 32, mReserved: 0)
        kernel.prepare(format)
        var samples = (0..<9600).map { Float(sin(2 * Double.pi * frequency * Double($0) / 48000) * 0.1) }
        samples.withUnsafeMutableBufferPointer { memory in
            var list = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(memory.count * 4), mData: memory.baseAddress))
            withUnsafeMutablePointer(to: &list) { kernel.process($0, frames: memory.count) }
        }
        return samples
    }
    private func rms(_ values: [Float]) -> Double { let data = values.dropFirst(2400); return sqrt(data.reduce(0) { $0 + Double($1 * $1) } / Double(data.count)) }
    func testNeutralPreservesSamples() {
        let a = render(frequency: 1000, config: PulseEQConfiguration())
        let b = render(frequency: 1000, config: PulseEQConfiguration(enabled: true))
        XCTAssertEqual(a, b)
    }
    func testBassPresetActuallyChangesFrequencyBalance() {
        let preset = PulseEQPreset.all.first { $0.id == "bass" }!
        let config = PulseEQConfiguration(enabled: true, gains: preset.gains, preset: preset.id)
        let low = rms(render(frequency: 64, config: config)), high = rms(render(frequency: 4000, config: config))
        XCTAssertGreaterThan(low, high * 1.3)
    }
    func testAllPresetsHaveFiniteSafeBands() {
        for preset in PulseEQPreset.all {
            XCTAssertEqual(preset.gains.count, 10)
            XCTAssertTrue(preset.gains.allSatisfy { $0.isFinite && abs($0) <= 9 })
            XCTAssertLessThanOrEqual(PulseEQConfiguration(enabled: true, gains: preset.gains).headroomDB, 0)
        }
    }
}

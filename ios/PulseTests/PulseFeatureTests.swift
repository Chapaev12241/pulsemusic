import XCTest
import AVFoundation
import AudioToolbox
import ImageIO
import UniformTypeIdentifiers
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

final class PulseFeatureContractTests: XCTestCase {
    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [PulseTestURLProtocol.self]
        return URLSession(configuration: config)
    }
    override func tearDown() { PulseTestURLProtocol.handler = nil; super.tearDown() }
    func testLyricsQueryPreservesCyrillicAndAmpersands() async throws {
        PulseTestURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/lyrics")
            let values = Dictionary(uniqueKeysWithValues: URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value!) })
            XCTAssertEqual(values["artist"], "Ёж & DJ")
            XCTAssertEqual(values["title"], "A+B? C")
            return (200, Data(#"{"found":false,"instrumental":false,"syncedLyrics":"","plainLyrics":"","source":"","sourceUrl":""}"#.utf8))
        }
        let result: PulseLyricsResponse = try await PulseAPI.request("api/lyrics", query: [URLQueryItem(name: "artist", value: "Ёж & DJ"), URLQueryItem(name: "title", value: "A+B? C")], session: session())
        XCTAssertFalse(result.found)
    }
    @MainActor
    func testSwitchingAccountsClearsSocialProfile() async {
        PulseTestURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer account-a-token")
            return (200, Data(##"{"profile":{"id":"account-a","name":"A","bio":"Private draft","color":"#a59aff","emoji":"♫","avatar":null},"friends":[],"incoming":[],"outgoing":[]}"##.utf8))
        }
        let store = PulseSocialStore(session: session())
        store.configure(token: "account-a-token", userID: "account-a")
        await store.refresh()
        XCTAssertEqual(store.profile?.id, "account-a")
        store.configure(token: "account-b-token", userID: "account-b")
        XCTAssertNil(store.profile)
        XCTAssertTrue(store.friends.isEmpty)
        store.configure(token: "", userID: "")
        XCTAssertFalse(store.signedIn)
    }
    func testSystemArtworkFallbackIsBundled() {
        XCTAssertNotNil(Bundle.main.url(forResource: "now-playing-fallback", withExtension: "png"))
    }
}

final class PulseAvatarEncodingTests: XCTestCase {
    func testAvatarMeetsServerJPEGContract() throws {
        let context = CGContext(data: nil, width: 900, height: 700, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(red: 0.5, green: 0.3, blue: 0.9, alpha: 1); context.fill(CGRect(x: 0, y: 0, width: 900, height: 700))
        let image = context.makeImage()!, encoded = NSMutableData()
        let destination = CGImageDestinationCreateWithData(encoded as CFMutableData, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil); XCTAssertTrue(CGImageDestinationFinalize(destination))
        let result = try PulseAvatarEncoder.jpeg(encoded as Data)
        XCTAssertLessThanOrEqual(result.count, 256000)
        XCTAssertEqual(Array(result.prefix(3)), [255,216,255])
        let decoded = CGImageSourceCreateWithData(result as CFData, nil)!
        let properties = CGImageSourceCopyPropertiesAtIndex(decoded, 0, nil)! as NSDictionary
        XCTAssertLessThanOrEqual(properties[kCGImagePropertyPixelWidth] as! Int, 512)
        XCTAssertLessThanOrEqual(properties[kCGImagePropertyPixelHeight] as! Int, 512)
    }
    func testInvalidAvatarDataIsRejected() { XCTAssertThrowsError(try PulseAvatarEncoder.jpeg(Data("not-an-image".utf8))) }
}

final class PulseChatSessionTests: XCTestCase {
    @MainActor
    func testOldChatCannotSendFromNewAccount() async {
        let social = PulseSocialStore()
        social.configure(token: "old-token", userID: "old-owner")
        let friend = PulseProfile(id: "friend", name: "Friend", bio: "", color: "#a59aff", emoji: "♫", avatar: nil, role: nil)
        let chat = PulseChatStore(friend: friend, social: social)
        XCTAssertTrue(chat.sessionValid)
        social.configure(token: "new-token", userID: "new-owner")
        XCTAssertFalse(chat.sessionValid)
        let result = await chat.send("This must never be sent")
        XCTAssertFalse(result)
        XCTAssertTrue(chat.messages.isEmpty)
    }
}

final class PulseSeekGestureTests: XCTestCase {
    func testSeekingNeverTriggersTrackSwipe() {
        let slider = CGRect(x: 20, y: 300, width: 320, height: 36)
        XCTAssertNil(PulseTrackSwipe.direction(horizontal: -150, vertical: 0, start: CGPoint(x: 100, y: 315), excluding: slider))
        XCTAssertEqual(PulseTrackSwipe.direction(horizontal: -150, vertical: 0, start: CGPoint(x: 100, y: 120), excluding: slider), 1)
    }
}

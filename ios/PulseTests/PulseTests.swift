import XCTest
import Combine
#if os(iOS)
@testable import Pulse
#else
@testable import PulseMac
#endif

final class PulseTests: XCTestCase {
    private func track(_ id: String, audio: String) throws -> PulseTrack {
        let data = try JSONSerialization.data(withJSONObject: ["id": id, "title": "Трек", "artist": "Артист", "audio": audio])
        return try JSONDecoder().decode(PulseTrack.self, from: data)
    }
    func testOwnedTrackReplacesPublicVersionWithoutDuplicates() throws {
        let publicTrack = try track("one", audio: "https://api.invalid/public")
        let owned = try track("one", audio: "https://api.invalid/private?signature=fresh")
        let extra = try track("two", audio: "https://api.invalid/private-two")
        let merged = PulseLibrary.merge(publicTracks: [publicTrack], ownedTracks: [owned, extra])
        XCTAssertEqual(merged.map(\.id), ["one", "two"])
        XCTAssertEqual(merged[0].audio, owned.audio)
    }
    func testHistoryAndPlaylistsPreserveOrderAndSkipDeletedTracks() throws {
        let tracks = try [track("a", audio: "a"), track("b", audio: "b")]
        XCTAssertEqual(PulseLibrary.ordered(["b", "gone", "b", "a"], in: tracks).map(\.id), ["b", "a"])
    }
    func testExistingWebsiteStateDecodes() throws {
        let data = Data(#"{"liked":["a"],"history":[{"id":"a","at":"2026-11-09T00:00:00Z"}],"playlists":[{"id":"p","name":"Дорога","tracks":["a"]}]}"#.utf8)
        let saved = try JSONDecoder().decode(PulseLibraryState.self, from: data)
        XCTAssertEqual(saved.liked, ["a"])
        XCTAssertEqual(saved.playlists.first?.name, "Дорога")
    }
    func testAPIUsesProductionHTTPSAndNoCustomDomainDependency() {
        XCTAssertEqual(PulseAPI.base.scheme, "https")
        XCTAssertEqual(PulseAPI.base.host, "pulse-vibe-music.desyatnichenkoiosyf2.chatgpt.site")
    }
}

final class PulseAPIContractTests: XCTestCase {
    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PulseTestURLProtocol.self]
        return URLSession(configuration: config)
    }
    override func tearDown() { PulseTestURLProtocol.handler = nil; super.tearDown() }
    func testLibraryRequestSendsBearerWithoutPuttingItInURL() async throws {
        PulseTestURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/music")
            XCTAssertNil(request.url?.query)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            return (200, Data(#"{"tracks":[]}"#.utf8))
        }
        let result: PulseCatalog = try await PulseAPI.request("api/music", token: "test-token", session: session())
        XCTAssertTrue(result.tracks.isEmpty)
    }
    func testLoginErrorPreservesServerMessageAndStatus() async throws {
        PulseTestURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            return (401, Data(#"{"error":"Неверный email или пароль"}"#.utf8))
        }
        do {
            let _: PulseSession = try await PulseAPI.request("api/auth/login", method: "POST", body: Data("{}".utf8), session: session())
            XCTFail("Expected a failed login")
        } catch let error as PulseAPIError {
            XCTAssertEqual(error.status, 401)
            XCTAssertEqual(error.message, "Неверный email или пароль")
        }
    }
}

final class PulseTestURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler, let url = request.url else { throw URLError(.badServerResponse) }
            let (status, data) = try handler(request)
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { }
}

final class PulsePerformanceTests: XCTestCase {
    @MainActor
    func testPendingKeychainReadDoesNotBlockTheMainActor() async {
        let entered = expectation(description: "Keychain read started in background")
        let gate = DispatchSemaphore(value: 0)
        let store = PulseStore(loadSession: {
            await Task.detached {
                entered.fulfill(); gate.wait(); return ""
            }.value
        })
        let restoration = Task { await store.restore() }
        await fulfillment(of: [entered], timeout: 2)
        // This code runs on MainActor while the simulated system read is stuck.
        XCTAssertFalse(store.signedIn)
        XCTAssertFalse(store.syncing)
        restoration.cancel(); gate.signal(); await restoration.value
    }
    @MainActor
    func testTransportTicksDoNotPublishLibraryChanges() async {
        let store = PulseStore()
        store.receivePlayback(["time": 0.0, "duration": 240.0, "paused": false, "id": "test"])
        var libraryChanges = 0
        let observation = store.objectWillChange.sink { libraryChanges += 1 }
        for tick in 1...120 {
            store.receivePlayback(["time": Double(tick) / 4, "duration": 240.0, "paused": false, "id": "test"])
        }
        XCTAssertEqual(store.playback.time, 30)
        XCTAssertEqual(libraryChanges, 0, "Playback ticks must not invalidate the library view")
        withExtendedLifetime(observation) { }
    }
    func testArtworkCacheKeysMatchWebsiteNormalization() {
        XCTAssertEqual(PulseArtworkCache.key(artist: " NOIZE MC ", title: "Ёж — Live!"), "noizemc|ежlive")
        XCTAssertEqual(PulseArtworkCache.key(artist: "Nirvana", title: "School"), "nirvana|school")
    }
}

#if os(macOS)
import AppKit
final class PulseTouchBarTests: XCTestCase {
    @MainActor
    func testWindowBarAndTransportAvailability() async {
        let store = PulseStore()
        let controller = PulseTouchBarController(store: store)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let original = window.touchBar
        controller.attach(to: window)
        XCTAssertTrue(window.touchBar === controller.bar)
        XCTAssertEqual(controller.bar.defaultItemIdentifiers.count, 5)
        let item = controller.touchBar(controller.bar, makeItemForIdentifier: PulseTouchBarController.Item.play) as? NSCustomTouchBarItem
        let button = item?.view as? NSButton
        XCTAssertEqual(button?.isEnabled, false)
        let data = Data(#"{"id":"test","title":"Test","artist":"Artist","audio":"https://example.invalid/audio"}"#.utf8)
        store.tracks = [try! JSONDecoder().decode(PulseTrack.self, from: data)]
        controller.refresh()
        XCTAssertEqual(button?.isEnabled, true)
        controller.detach()
        XCTAssertTrue(window.touchBar === original)
    }
    @MainActor
    func testVolumeSliderUsesPlayerSetting() async {
        let store = PulseStore()
        let controller = PulseTouchBarController(store: store)
        let item = controller.touchBar(controller.bar, makeItemForIdentifier: PulseTouchBarController.Item.volume) as? NSCustomTouchBarItem
        let slider = (item?.view as? NSStackView)?.arrangedSubviews.compactMap { $0 as? NSSlider }.first
        XCTAssertNotNil(slider)
        slider?.doubleValue = 0.35
        if let slider { controller.changeVolume(slider) }
        XCTAssertEqual(store.volume, 0.35, accuracy: 0.001)
    }
}
#endif

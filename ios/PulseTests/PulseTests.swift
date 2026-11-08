import XCTest
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

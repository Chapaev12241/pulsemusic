import XCTest
#if os(iOS)
@testable import Pulse
#else
@testable import PulseMac
#endif
final class PulseCollectionsTests: XCTestCase {
    func testOldLibraryStateKeepsLikesAndAllowsNewCoverMetadata() throws {
        let old = try JSONDecoder().decode(PulseLibraryState.self, from: Data(#"{"liked":["one"],"history":[],"playlists":[]}"#.utf8))
        XCTAssertEqual(old.liked, ["one"]); XCTAssertEqual(old.playlistCovers, [:])
        var state = old; state.playlistCovers["liked"] = "custom-cover"
        let copy = try JSONDecoder().decode(PulseLibraryState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(copy, state)
    }
    @MainActor
    func testBuiltInPlaylistsHaveIndependentCoversAndDynamicMembership() throws {
        let store = PulseStore(loadSession: { "" })
        let song = try JSONDecoder().decode(PulseTrack.self, from: Data(#"{"id":"one","title":"One","artist":"Artist","audio":"https://test.invalid/audio"}"#.utf8))
        store.tracks = [song]; store.ownedIDs = ["one"]; store.state.playlistCovers["liked"] = "liked-cover"
        var items = PulsePlaylistItem.all(store: store)
        XCTAssertEqual(items.first { $0.id == "library" }?.tracks.map(\.id), ["one"])
        XCTAssertEqual(items.first { $0.id == "liked" }?.tracks.count, 0)
        store.state.liked = ["one"]; items = PulsePlaylistItem.all(store: store)
        XCTAssertEqual(items.first { $0.id == "liked" }?.tracks.map(\.id), ["one"])
        XCTAssertEqual(items.first { $0.id == "liked" }?.cover, "liked-cover")
        XCTAssertNil(items.first { $0.id == "library" }?.cover)
    }
    func testArtistCollectionsContainOnlyThatArtistAndMoodsUseKnownGenres() throws {
        func track(_ id: String, _ artist: String, _ genre: String) throws -> PulseTrack {
            try JSONDecoder().decode(PulseTrack.self, from: JSONSerialization.data(withJSONObject: ["id":id,"artist":artist,"title":id,"audio":"https://test.invalid/audio","genres":[genre]]))
        }
        let songs = try [track("a", "Artist A", "ambient"), track("b", "Artist A", "jazz"), track("c", "Artist B", "metal")]
        let collections = PulseMusicCollection.make(songs)
        XCTAssertEqual(collections.first { $0.id == "artist-Artist A" }?.tracks.map(\.id), ["a","b"])
        XCTAssertEqual(collections.first { $0.id == "mood-calm" }?.tracks.map(\.id), ["a","b"])
        XCTAssertEqual(collections.first { $0.id == "mood-energy" }?.tracks.map(\.id), ["c"])
        XCTAssertNil(collections.first { $0.id == "mood-romance" })
    }
}

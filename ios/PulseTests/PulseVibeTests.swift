import XCTest
#if os(iOS)
@testable import Pulse
#else
@testable import PulseMac
#endif
final class PulseVibeTests: XCTestCase {
    private func track(_ id: String, _ artist: String, genre: String = "rap") throws -> PulseTrack {
        try JSONDecoder().decode(PulseTrack.self, from: JSONSerialization.data(withJSONObject: ["id":id,"title":"Song \(id)","artist":artist,"genres":[genre],"audio":"https://example.invalid/\(id).mp3"]))
    }
    func testArtistPlaylistNeverLeaksOtherArtistsOrInventedIDs() throws {
        let tracks = try [track("a","Гуф"),track("b","Гуф"),track("c","Баста")]
        let input = try PulseVibe.prepare(tracks: tracks, state: PulseLibraryState(), prompt: "Все песни", mode: .artist, seed: "Гуф", discovery: 0.5, variation: 1)
        let plan = PulseAIPlan(name: "Гуф", summary: "Подборка", artists: [999,0,0])
        let draft = try PulseVibe.draft(plan, input: input)
        XCTAssertEqual(Set(draft.tracks), Set(["a","b"]))
        XCTAssertEqual(draft.artists,["Гуф"])
    }
    func testSimilarPlaylistBalancesArtistsAndKeepsSeed() throws {
        let tracks = try [track("a","Гуф"),track("b","Баста"),track("c","Мот"),track("d","Баста")]
        let input = try PulseVibe.prepare(tracks: tracks, state: PulseLibraryState(), prompt: "Рэп", mode: .similar, seed: "Гуф", discovery: 0.8, variation: 2)
        let indexes = input.artists.indices.filter { input.artists[$0].name != "Гуф" }
        let draft = try PulseVibe.draft(PulseAIPlan(name: "Рядом", summary: "Рэп", artists: indexes + indexes + [999]), input: input)
        XCTAssertTrue(draft.artists.contains("Гуф")); XCTAssertEqual(draft.tracks.count,Set(draft.tracks).count)
        XCTAssertTrue(Set(draft.tracks).isSubset(of: Set(tracks.map(\.id))))
    }
    func testPersonalPreferencesAffectContextWithoutChangingLibrary() throws {
        let tracks = try [track("a","Liked"),track("b","Other")]
        var state = PulseLibraryState(); state.liked = ["a"]
        let input = try PulseVibe.prepare(tracks: tracks, state: state, prompt: "Night", mode: .personal, seed: "", discovery: 0.5, variation: 1)
        XCTAssertEqual(input.artists.first?.name,"Liked")
        XCTAssertTrue(try PulseVibe.prompt(input).contains("Night"))
        XCTAssertThrowsError(try PulseVibe.prepare(tracks: [], state: state, prompt: "", mode: .personal, seed: "", discovery: 0.5))
    }
    func testRealLocalModelProducesBoundedPlayablePlaylist() async throws {
        let cached = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cache/pulse-ai/Qwen3-1.7B-Q4_K_M.gguf").path
        let path = ProcessInfo.processInfo.environment["PULSE_AI_TEST_MODEL"] ?? cached
        guard FileManager.default.fileExists(atPath: path) else { throw XCTSkip("Real-model smoke test runs in CI with a verified model file") }
        let tracks = try [track("a","Гуф"),track("b","Баста"),track("c","Мот"),track("d","Metallica",genre:"metal")]
        var state = PulseLibraryState(); state.liked = ["a"]
        let input = try PulseVibe.prepare(tracks: tracks,state: state,prompt:"Русский рэп, похожий на Гуфа",mode:.similar,seed:"Гуф",discovery:0.7,variation:4)
        let result = try await PulseLocalAI.shared.generate(input:input,modelURL:URL(fileURLWithPath:path),playing:true)
        XCTAssertFalse(result.name.isEmpty); XCTAssertFalse(result.summary.isEmpty); XCTAssertFalse(result.tracks.isEmpty)
        XCTAssertTrue(Set(result.tracks).isSubset(of:Set(tracks.map(\.id))))
        XCTAssertTrue(result.artists.contains("Гуф"))
        XCTAssertTrue(result.artists.contains("Баста") || result.artists.contains("Мот"))
        XCTAssertFalse(result.artists.contains("Metallica"))
    }
}

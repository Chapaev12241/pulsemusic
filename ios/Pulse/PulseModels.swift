import Foundation

struct PulseTrack: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let artist: String
    let album: String?
    let genres: [String]?
    let artwork: String?
    let audio: String
    var artworkURL: URL? { artwork.flatMap(URL.init(string:)) }
    var nativeValue: [String: Any] {
        ["id": id, "title": title, "artist": artist, "album": album ?? "", "artwork": artwork ?? "", "audio": audio]
    }
}
struct PulseUser: Codable { let id: String; let email: String; let name: String }
struct PulseSession: Decodable { let user: PulseUser; let token: String }
struct PulseIdentity: Decodable { let authenticated: Bool; let user: PulseUser? }
struct PulseCatalog: Decodable { let tracks: [PulseTrack]; let indexing: Bool? }
struct PulsePlaylist: Codable, Identifiable { let id: String; let name: String; let tracks: [String] }
struct PulseHistory: Codable { let id: String; let at: String }
struct PulseLibraryState: Codable {
    var liked: [String] = []
    var history: [PulseHistory] = []
    var playlists: [PulsePlaylist] = []
}
struct PulseOK: Decodable { let ok: Bool? }
struct PulseUpload: Decodable { let id: String; let duplicate: Bool? }
struct PulseAPIError: LocalizedError {
    let status: Int
    let message: String
    var errorDescription: String? { message }
}
enum PulseCollection: String, CaseIterable, Identifiable {
    case catalog, library, liked, playlists, history
    var id: String { rawValue }
    var title: String {
        switch self {
        case .catalog: return "Вся музыка"
        case .library: return "Моя медиатека"
        case .liked: return "Избранное"
        case .playlists: return "Плейлисты"
        case .history: return "История"
        }
    }
    var symbol: String {
        switch self {
        case .catalog: return "sparkles"
        case .library: return "music.note.list"
        case .liked: return "heart.fill"
        case .playlists: return "rectangle.stack.fill"
        case .history: return "clock"
        }
    }
}
enum PulseLibrary {
    static func merge(publicTracks: [PulseTrack], ownedTracks: [PulseTrack]) -> [PulseTrack] {
        var values = publicTracks
        var positions = Dictionary(uniqueKeysWithValues: values.enumerated().map { ($0.element.id, $0.offset) })
        for track in ownedTracks {
            if let position = positions[track.id] { values[position] = track }
            else { positions[track.id] = values.count; values.append(track) }
        }
        return values
    }
    static func ordered(_ ids: [String], in tracks: [PulseTrack]) -> [PulseTrack] {
        let values = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        var seen = Set<String>()
        return ids.compactMap { seen.insert($0).inserted ? values[$0] : nil }
    }
}

import Foundation

struct PulseTrack: Codable, Identifiable, Hashable, Sendable {
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
struct PulsePlaylist: Codable, Identifiable, Equatable, Sendable { let id: String; let name: String; let tracks: [String]; var cover: String? = nil }
struct PulseHistory: Codable, Equatable, Sendable { let id: String; let at: String }
struct PulseLibraryState: Codable, Equatable {
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
    case home, search, vibe, dj, catalog, library, liked, playlists, history, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: return "Главная"
        case .catalog: return "Вся музыка"
        case .library: return "Моя медиатека"
        case .liked: return "Понравилось"
        case .playlists: return "Плейлисты"
        case .history: return "История"
        case .search: return "Поиск"
        case .vibe: return "Мой вайб"
        case .dj: return "DJ"
        case .settings: return "Настройки"
        }
    }
    var symbol: String {
        switch self {
        case .home: return "house"
        case .catalog: return "square.grid.2x2"
        case .library: return "music.note.list"
        case .liked: return "heart.fill"
        case .playlists: return "rectangle.stack.fill"
        case .history: return "clock"
        case .search: return "magnifyingglass"
        case .vibe: return "sparkles"
        case .dj: return "waveform"
        case .settings: return "slider.horizontal.3"
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

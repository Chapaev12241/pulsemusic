import SwiftUI

struct PulseMusicCollection: Identifiable {
    let id: String, name: String, caption: String
    let tracks: [PulseTrack]
    static func make(_ tracks: [PulseTrack]) -> [PulseMusicCollection] {
        let moods: [(String, String, [String])] = [
            ("calm", "На спокойной волне", ["ambient", "chill", "jazz", "classical", "acoustic", "lo-fi", "downtempo"]),
            ("energy", "Заряд энергии", ["rock", "punk", "metal", "dance", "edm", "techno", "house", "phonk", "drum"]),
            ("night", "Ночной город", ["synth", "electronic", "r&b", "soul", "trap", "hip-hop", "hip hop", "rap", "рэп"]),
            ("romance", "Ближе друг к другу", ["pop", "indie", "soul", "rnb", "acoustic"])
        ]
        var result = moods.compactMap { id, name, genres -> PulseMusicCollection? in
            let list = tracks.filter { track in (track.genres ?? []).contains { genre in genres.contains { genre.lowercased().contains($0) } } }
            return list.isEmpty ? nil : PulseMusicCollection(id: "mood-" + id, name: name, caption: "Под настроение", tracks: Array(list.prefix(60)))
        }
        let artists = Dictionary(grouping: tracks, by: \.artist).sorted { a, b in a.value.count == b.value.count ? a.key < b.key : a.value.count > b.value.count }
        result += artists.prefix(12).map { PulseMusicCollection(id: "artist-" + $0.key, name: $0.key, caption: "Коллекция исполнителя", tracks: $0.value) }
        return result
    }
}
struct PulseCollectionPage: View {
    @ObservedObject var store: PulseStore
    let collection: PulseMusicCollection
    @Environment(\.dismiss) private var dismiss
    @State private var saved = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack { Text(collection.caption).font(.caption).foregroundStyle(PulseTheme.muted); Spacer(); Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 36, height: 36) }.buttonStyle(PulseTactileButton()) }
                PulseArtworkView(track: collection.tracks.first, size: 200, radius: 24).frame(maxWidth: .infinity)
                Text(collection.name).font(.system(size: 30, weight: .bold))
                Text(PulseLibrary.trackCount(collection.tracks.count)).font(.caption).foregroundStyle(PulseTheme.muted)
                HStack {
                    Button { if let first = collection.tracks.first { store.play(first, within: collection.tracks) } } label: { Label("Слушать", systemImage: "play.fill") }.buttonStyle(PulsePrimaryButton())
                    Button(saved ? "Сохранено" : "В плейлисты") { store.createPlaylist(collection.name, tracks: Array(collection.tracks.prefix(2000).map(\.id))); saved = store.signedIn }.buttonStyle(PulseTactileButton()).disabled(saved)
                }
                LazyVStack(spacing: 0) { ForEach(Array(collection.tracks.enumerated()), id: \.element.id) { index, track in PulseTrackRow(track: track, index: index + 1) { store.play(track, within: collection.tracks) }; Divider().overlay(PulseTheme.line) } }
            }.padding(24)
        }.background(PulseAmbientBackground())
        #if os(macOS)
        .frame(width: 640, height: 740)
        #endif
    }
}

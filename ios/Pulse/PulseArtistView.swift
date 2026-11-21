import SwiftUI

// Artist identities use the same normalization in search, player links and pages.
enum PulseArtistCatalog {
    static func tracks(for artist: String, in tracks: [PulseTrack]) -> [PulseTrack] {
        let key = PulseSearch.key(artist)
        guard !key.isEmpty else { return [] }
        return tracks.filter { PulseSearch.key($0.artist) == key }
    }
    static func names(in tracks: [PulseTrack]) -> [String] {
        var seen = Set<String>()
        return tracks.compactMap { track -> String? in
            let name = track.artist.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = PulseSearch.key(name)
            return !key.isEmpty && seen.insert(key).inserted ? name : nil
        }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}

struct PulseArtistSelection: Identifiable {
    let name: String
    var id: String { PulseSearch.key(name) }
}

struct PulseArtistPortrait: View {
    let artist: String
    let tracks: [PulseTrack]
    var size: CGFloat = 148
    @State private var portrait: CGImage?
    private var artworkTracks: [PulseTrack] {
        var seen = Set<String>()
        return Array(tracks.filter { seen.insert($0.artwork ?? $0.id).inserted }.prefix(4))
    }
    var body: some View {
        ZStack {
            Circle().fill(PulseTheme.raised)
            if let portrait {
                Image(decorative: portrait, scale: 1).resizable().scaledToFill()
            } else if artworkTracks.count > 1 {
                let gap: CGFloat = 2
                let tile = (size - gap) / 2
                VStack(spacing: gap) {
                    HStack(spacing: gap) { artwork(at: 0, size: tile); artwork(at: 1, size: tile) }
                    HStack(spacing: gap) { artwork(at: 2, size: tile); artwork(at: 3, size: tile) }
                }
            } else if let track = artworkTracks.first {
                PulseArtworkView(track: track, size: size, radius: 0)
            } else {
                Image(systemName: "music.mic").font(.system(size: size * 0.3, weight: .light)).foregroundStyle(PulseTheme.muted)
            }
        }
        .frame(width: size, height: size).clipShape(Circle())
        .overlay(Circle().strokeBorder(PulseTheme.line))
        .task(id: PulseSearch.key(artist)) {
            portrait = nil
            // Empty title requests artist artwork through the existing cache and lookup endpoint.
            let lookup = PulseTrack(id: "artist-" + PulseSearch.key(artist), title: "", artist: artist, album: nil, genres: nil, artwork: nil, audio: "")
            let image = await PulseArtworkCache.shared.image(for: lookup)
            if !Task.isCancelled { portrait = image }
        }
        .accessibilityLabel(portrait == nil ? "Обложки релизов \(artist)" : "Изображение исполнителя \(artist)")
    }
    private func artwork(at index: Int, size: CGFloat) -> some View {
        PulseArtworkView(track: artworkTracks[index % artworkTracks.count], size: size, radius: 0)
    }
}

struct PulseArtistCard: View {
    @ObservedObject var store: PulseStore
    let artist: String
    var size: CGFloat = 148
    var onOpen: (() -> Void)? = nil
    @State private var showing = false
    @State private var hovered = false
    @Environment(\.pulseReducedMotion) private var reducedMotion
    private var tracks: [PulseTrack] { PulseArtistCatalog.tracks(for: artist, in: store.tracks) }
    var body: some View {
        Button {
            onOpen?()
            showing = true
        } label: {
            VStack(spacing: 14) {
                PulseArtistPortrait(artist: artist, tracks: tracks, size: max(72, size - 20))
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "arrow.up.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(PulseTheme.text)
                            .frame(width: 32, height: 32).background(PulseTheme.raised, in: Circle())
                            .opacity(hovered ? 1 : 0).accessibilityHidden(true)
                    }
                VStack(spacing: 6) {
                    Text(artist).font(PulseTheme.body(15, weight: .semibold)).foregroundStyle(PulseTheme.text).lineLimit(2).multilineTextAlignment(.center)
                    Text(PulseLibrary.trackCount(tracks.count)).font(PulseTheme.body(12)).foregroundStyle(PulseTheme.muted)
                }.frame(height: 57, alignment: .top)
            }.frame(width: max(72, size - 20)).padding(10)
                .background(hovered ? PulseTheme.panel : .clear, in: RoundedRectangle(cornerRadius: 24))
        }
        .buttonStyle(PulseTactileButton()).onHover { hovered = $0 }
        .animation(reducedMotion ? nil : .easeOut(duration: 0.18), value: hovered)
        .accessibilityLabel("Исполнитель \(artist), \(PulseLibrary.trackCount(tracks.count))")
        .sheet(isPresented: $showing) {
            PulseArtistPage(store: store, artist: artist).environmentObject(store).preferredColorScheme(.dark).tint(PulseTheme.accent)
        }
    }
}

struct PulseArtistPage: View {
    @ObservedObject var store: PulseStore
    let artist: String
    @Environment(\.dismiss) private var dismiss
    @State private var selectedAlbum: PulseArtistAlbum?
    private var tracks: [PulseTrack] { PulseArtistCatalog.tracks(for: artist, in: store.tracks) }
    private var albums: [PulseArtistAlbum] { PulseArtistAlbum.make(tracks) }
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    hero
                    HStack(spacing: 12) {
                        Button { play(shuffled: false) } label: {
                            Label("Слушать", systemImage: "play.fill").frame(maxWidth: .infinity)
                        }.buttonStyle(PulsePrimaryButton())
                        Button { play(shuffled: true) } label: {
                            Image(systemName: "shuffle").font(.system(size: 20, weight: .medium)).frame(width: 52, height: 48)
                                .background(PulseTheme.raised, in: RoundedRectangle(cornerRadius: 18))
                        }.buttonStyle(PulseTactileButton(feedback: .shuffle)).accessibilityLabel("Перемешать треки исполнителя")
                    }.disabled(tracks.isEmpty)
                    if !albums.isEmpty { albumShelf }
                    HStack {
                        Text("Все треки").font(PulseTheme.body(24, weight: .bold))
                        Spacer()
                        Text(PulseLibrary.trackCount(tracks.count)).font(PulseTheme.body(12)).foregroundStyle(PulseTheme.muted)
                    }
                    if tracks.isEmpty {
                        ContentUnavailableView("Треки ещё не добавлены", systemImage: "music.note", description: Text("Музыка исполнителя появится здесь вместе с обновлением медиатеки."))
                    } else {
                        PulseArtistTrackList(store: store, tracks: tracks)
                    }
                }.padding(24).frame(maxWidth: 960).frame(maxWidth: .infinity)
            }
            .refreshable { await store.refresh() }
            .background(PulseAmbientBackground())
            .navigationTitle("Исполнитель")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
        .environmentObject(store).foregroundStyle(PulseTheme.text)
        .sheet(item: $selectedAlbum) { album in
            PulseArtistAlbumPage(store: store, artist: artist, album: album).environmentObject(store).preferredColorScheme(.dark).tint(PulseTheme.accent)
        }
        #if os(macOS)
        .frame(minWidth: 640, idealWidth: 780, minHeight: 620, idealHeight: 780)
        #endif
    }
    private var hero: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                PulseTheme.panel
                PulseArtistPortrait(artist: artist, tracks: tracks, size: min(380, max(260, geometry.size.width * 0.65)))
                    .opacity(0.82).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(.top, -20).padding(.trailing, -18)
                LinearGradient(colors: [PulseTheme.background.opacity(0.04), PulseTheme.background.opacity(0.55), PulseTheme.background.opacity(0.96)], startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Исполнитель").font(PulseTheme.body(13, weight: .medium)).foregroundStyle(PulseTheme.muted)
                    Text(artist).font(PulseTheme.display(40)).lineLimit(3).minimumScaleFactor(0.6).fixedSize(horizontal: false, vertical: true)
                    Text(PulseLibrary.trackCount(tracks.count)).font(PulseTheme.body(14)).foregroundStyle(PulseTheme.muted)
                }.padding(26)
            }.clipShape(RoundedRectangle(cornerRadius: 30))
        }.frame(height: 320)
    }
    private var albumShelf: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Альбомы и релизы").font(PulseTheme.body(24, weight: .bold))
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 18) {
                    ForEach(albums) { album in
                        Button { selectedAlbum = album } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                PulseArtworkView(track: album.tracks.first, size: 148, radius: 20)
                                Text(album.name).font(PulseTheme.body(14, weight: .semibold)).foregroundStyle(PulseTheme.text).lineLimit(2)
                                Text(PulseLibrary.trackCount(album.tracks.count)).font(PulseTheme.body(12)).foregroundStyle(PulseTheme.muted)
                            }.frame(width: 148, alignment: .leading)
                        }.buttonStyle(PulseTactileButton()).accessibilityLabel("Альбом \(album.name)")
                    }
                }.padding(.vertical, 2)
            }
        }
    }
    private func play(shuffled: Bool) {
        guard let first = shuffled ? tracks.randomElement() : tracks.first else { return }
        store.shuffle = shuffled
        store.play(first, within: tracks)
    }
}

private struct PulseArtistAlbum: Identifiable {
    let id: String
    let name: String
    let tracks: [PulseTrack]
    static func make(_ tracks: [PulseTrack]) -> [PulseArtistAlbum] {
        let unknown = Set(["unknown", "unknown album", "неизвестный альбом", "без альбома"])
        let known = tracks.filter { track in
            guard let album = track.album else { return false }
            let key = PulseSearch.key(album)
            return !key.isEmpty && !unknown.contains(key)
        }
        return Dictionary(grouping: known, by: { PulseSearch.key($0.album ?? "") }).map { key, values in
            PulseArtistAlbum(id: key, name: values.first?.album?.trimmingCharacters(in: .whitespacesAndNewlines) ?? key, tracks: values)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

private struct PulseArtistTrackList: View {
    @ObservedObject var store: PulseStore
    let tracks: [PulseTrack]
    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                PulseTrackRow(track: track, index: index + 1) { store.play(track, within: tracks) }
                Rectangle().fill(PulseTheme.line).frame(height: 1).padding(.leading, 72)
            }
        }
    }
}

private struct PulseArtistAlbumPage: View {
    @ObservedObject var store: PulseStore
    let artist: String
    let album: PulseArtistAlbum
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    PulseArtworkView(track: album.tracks.first, size: 220, radius: 28).frame(maxWidth: .infinity)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(album.name).font(PulseTheme.display(30)).lineLimit(3)
                        Text(artist).font(PulseTheme.body(16, weight: .medium)).foregroundStyle(PulseTheme.muted)
                        Text(PulseLibrary.trackCount(album.tracks.count)).font(PulseTheme.body(12)).foregroundStyle(PulseTheme.muted)
                    }
                    Button {
                        if let first = album.tracks.first { store.shuffle = false; store.play(first, within: album.tracks) }
                    } label: { Label("Слушать релиз", systemImage: "play.fill") }.buttonStyle(PulsePrimaryButton())
                    PulseArtistTrackList(store: store, tracks: album.tracks)
                }.padding(24).frame(maxWidth: 780).frame(maxWidth: .infinity)
            }.background(PulseAmbientBackground()).navigationTitle("Релиз")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }.foregroundStyle(PulseTheme.text)
        #if os(macOS)
        .frame(minWidth: 600, idealWidth: 700, minHeight: 620, idealHeight: 760)
        #endif
    }
}

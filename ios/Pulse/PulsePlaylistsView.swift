import SwiftUI
import UniformTypeIdentifiers

struct PulsePlaylistItem: Identifiable {
    let id: String, name: String, symbol: String
    let tracks: [PulseTrack]
    let cover: String?
    @MainActor static func all(store: PulseStore) -> [PulsePlaylistItem] {
        [PulsePlaylistItem(id: "liked", name: "Понравилось", symbol: "heart.fill", tracks: PulseLibrary.ordered(store.state.liked, in: store.tracks), cover: store.state.playlistCovers["liked"]),
         PulsePlaylistItem(id: "library", name: "Моя музыка", symbol: "music.note.list", tracks: store.tracks.filter { store.ownedIDs.contains($0.id) }, cover: store.state.playlistCovers["library"]),
         PulsePlaylistItem(id: "downloads", name: "Скачано", symbol: "arrow.down.circle.fill", tracks: store.downloads.tracks, cover: store.state.playlistCovers["downloads"])] + store.state.playlists.map { PulsePlaylistItem(id: $0.id, name: $0.name, symbol: "music.note.list", tracks: PulseLibrary.ordered($0.tracks, in: store.tracks), cover: $0.cover) }
    }
}
struct PulsePlaylistsView: View {
    @ObservedObject var store: PulseStore
    @State private var selected: String?
    @State private var coverTarget: String?
    @State private var choosingCover = false
    @State private var creating = false
    @State private var showingAI = false
    @State private var name = ""
    private var items: [PulsePlaylistItem] { PulsePlaylistItem.all(store: store) }
    private var item: PulsePlaylistItem? { items.first { $0.id == selected } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let item {
                    Button { selected = nil } label: { Label("Плейлисты", systemImage: "chevron.left") }.buttonStyle(PulseTactileButton())
                    VStack(spacing: 20) {
                        Button { chooseCover(item.id) } label: { PulsePlaylistCover(cover: item.cover, size: 208, symbol: item.symbol).overlay(alignment: .bottomTrailing) { Image(systemName: "camera.fill").padding(10).background(.black.opacity(0.65), in: Circle()).padding(10) } }.buttonStyle(PulseTactileButton()).accessibilityLabel("Изменить обложку плейлиста")
                        VStack(spacing: 8) { Text(item.name).font(.system(size: 30, weight: .bold)).multilineTextAlignment(.center); Text("\(item.tracks.count) треков").font(.system(size: 13)).foregroundStyle(PulseTheme.muted) }
                        HStack(spacing: 14) {
                            Button { if let first = item.tracks.first { store.play(first, within: item.tracks) } } label: { Label("Слушать", systemImage: "play.fill").frame(minWidth: 110) }.buttonStyle(PulsePrimaryButton())
                            Button { store.shuffle = true; if let first = item.tracks.randomElement() { store.play(first, within: item.tracks) } } label: { Image(systemName: "shuffle").frame(width: 44, height: 44).background(PulseTheme.raised, in: Circle()) }.buttonStyle(PulseTactileButton(feedback: .shuffle)).accessibilityLabel("Перемешать плейлист")
                        }.disabled(item.tracks.isEmpty)
                    }.frame(maxWidth: .infinity).padding(.vertical, 8)
                    if item.tracks.isEmpty { Text("Здесь пока нет треков").foregroundStyle(PulseTheme.muted).frame(maxWidth: .infinity).padding(30) }
                    LazyVStack(spacing: 0) { ForEach(Array(item.tracks.enumerated()), id: \.element.id) { index, track in PulseTrackRow(track: track, index: index + 1) { store.play(track, within: item.tracks) }; Divider().overlay(PulseTheme.line) } }
                } else {
                    HStack { Text("Плейлисты").font(PulseTheme.heading(36)); Spacer(); Menu { Button("Новый плейлист") { creating = true }; Button("Подобрать с ИИ") { showingAI = true } } label: { Image(systemName: "plus").frame(width: 42, height: 42).background(PulseTheme.raised, in: Circle()) }.buttonStyle(PulseTactileButton()).accessibilityLabel("Создать плейлист") }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 145, maximum: 240), spacing: 20)], alignment: .leading, spacing: 26) {
                        ForEach(items) { item in
                            Button { selected = item.id } label: {
                                VStack(alignment: .leading, spacing: 10) {
                                    GeometryReader { proxy in PulsePlaylistCover(cover: item.cover, size: proxy.size.width, symbol: item.symbol) }.aspectRatio(1, contentMode: .fit)
                                    Text(item.name).font(.system(size: 15, weight: .semibold)).lineLimit(2)
                                    Text("\(item.tracks.count) треков").font(.system(size: 12)).foregroundStyle(PulseTheme.muted)
                                }.contentShape(Rectangle())
                            }.buttonStyle(PulseTactileButton()).contextMenu { Button("Изменить обложку", systemImage: "photo") { chooseCover(item.id) } }
                        }
                    }
                }
            }.padding(24)
        }.refreshable { await store.refresh() }
        .fileImporter(isPresented: $choosingCover, allowedContentTypes: [.image]) { result in if case .success(let url) = result, let id = coverTarget { Task { await store.setPlaylistCover(id, url: url) } } }
        .sheet(isPresented: $showingAI) { PulseVibeView(store: store).preferredColorScheme(.dark).tint(PulseTheme.accent) }
        .alert("Новый плейлист", isPresented: $creating) { TextField("Название", text: $name); Button("Создать") { let value = name.trimmingCharacters(in: .whitespacesAndNewlines); if !value.isEmpty { store.createPlaylist(value); name = "" } }; Button("Отмена", role: .cancel) {} }
        .onChange(of: store.state.playlists.map(\.id)) { _, _ in if selected != nil && item == nil { selected = nil } }
    }
    private func chooseCover(_ id: String) { coverTarget = id; choosingCover = true }
}

import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import PhotosUI
#endif

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
    @Environment(\.pulseReducedMotion) private var reducedMotion
    @State private var selected: String?
    @State private var coverTarget: String?
    @State private var choosingCover = false
    @State private var creating = false
    @State private var showingAI = false
    @State private var addingTracks = false
    private var items: [PulsePlaylistItem] { PulsePlaylistItem.all(store: store) }
    private var item: PulsePlaylistItem? { items.first { $0.id == selected } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let item {
                    Button { selected = nil } label: { Label("Плейлисты", systemImage: "chevron.left") }.buttonStyle(PulseTactileButton())
                    playlistHeader(item)
                    if item.tracks.isEmpty { Text("Здесь пока нет треков").foregroundStyle(PulseTheme.muted).frame(maxWidth: .infinity).padding(30) }
                    LazyVStack(spacing: 0) { ForEach(Array(item.tracks.enumerated()), id: \.element.id) { index, track in PulseTrackRow(track: track, index: index + 1) { store.play(track, within: item.tracks) }; Divider().overlay(PulseTheme.line) } }
                } else {
                    HStack { Text("Плейлисты").font(PulseTheme.display(36)); Spacer(); creationMenu }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 145, maximum: 240), spacing: 20)], alignment: .leading, spacing: 26) {
                        ForEach(items) { item in
                            Button { selected = item.id } label: {
                                VStack(alignment: .leading, spacing: 10) {
                                    GeometryReader { proxy in PulsePlaylistCover(cover: item.cover, size: proxy.size.width, symbol: item.symbol, fallback: item.tracks.first) }.aspectRatio(1, contentMode: .fit)
                                    Text(item.name).font(PulseTheme.body(15, weight: .semibold)).lineLimit(2)
                                    Text(PulseLibrary.trackCount(item.tracks.count)).font(PulseTheme.body(12)).foregroundStyle(PulseTheme.muted)
                                }.contentShape(Rectangle())
                            }.buttonStyle(PulseTactileButton()).contextMenu { Button("Изменить обложку", systemImage: "photo") { chooseCover(item.id) } }
                        }
                    }
                }
            }.padding(24)
            .animation(reducedMotion ? nil : .easeInOut(duration: 0.22), value: selected)
        }.refreshable { await store.refresh() }
        .fileImporter(isPresented: $choosingCover, allowedContentTypes: [.image]) { result in if case .success(let url) = result, let id = coverTarget { Task { await store.setPlaylistCover(id, url: url) } } }
        .sheet(isPresented: $showingAI) { PulseVibeView(store: store).preferredColorScheme(.dark).tint(PulseTheme.accent) }
        .sheet(isPresented: $creating) {
            PulsePlaylistCreateSheet(store: store) { id in selected = id; creating = false }.preferredColorScheme(.dark).tint(PulseTheme.accent)
        }
        .sheet(isPresented: $addingTracks) {
            if let id = selected { PulsePlaylistTrackPicker(store: store, playlistID: id).preferredColorScheme(.dark).tint(PulseTheme.accent) }
        }
        .onChange(of: store.user?.id) { _, _ in creating = false; addingTracks = false }
        .onChange(of: store.state.playlists.map(\.id)) { _, _ in if selected != nil && item == nil { selected = nil } }
    }
    private func playlistHeader(_ item: PulsePlaylistItem) -> some View {
        Group {
            #if os(macOS)
            HStack(alignment: .bottom, spacing: 30) { coverButton(item); playlistInfo(item).frame(maxWidth: .infinity, alignment: .leading) }
            #else
            VStack(spacing: 22) { coverButton(item); playlistInfo(item) }.frame(maxWidth: .infinity)
            #endif
        }.padding(.vertical, 12)
    }
    private func coverButton(_ item: PulsePlaylistItem) -> some View {
        Button { chooseCover(item.id) } label: {
            PulsePlaylistCover(cover: item.cover, size: 208, symbol: item.symbol, fallback: item.tracks.first)
        }.buttonStyle(PulseTactileButton()).accessibilityLabel("Изменить обложку плейлиста")
            .help("Изменить обложку")
    }
    private func playlistInfo(_ item: PulsePlaylistItem) -> some View {
        VStack(alignment: infoAlignment, spacing: 12) {
            Text(item.name).font(PulseTheme.display(34)).multilineTextAlignment(infoTextAlignment).fixedSize(horizontal: false, vertical: true)
            Text(PulseLibrary.trackCount(item.tracks.count)).font(PulseTheme.body(14)).foregroundStyle(PulseTheme.muted)
            HStack(spacing: 14) {
                Button { if let first = item.tracks.first { store.play(first, within: item.tracks) } } label: { Label("Слушать", systemImage: "play.fill").frame(minWidth: 100) }.buttonStyle(PulsePrimaryButton())
                Button { store.shuffle = true; if let first = item.tracks.randomElement() { store.play(first, within: item.tracks) } } label: { Image(systemName: "shuffle").frame(width: 48, height: 48).background(PulseTheme.raised, in: Circle()) }.buttonStyle(PulseTactileButton(feedback: .shuffle)).accessibilityLabel("Перемешать плейлист")
            }.disabled(item.tracks.isEmpty).padding(.top, 8)
            if store.state.playlists.contains(where: { $0.id == item.id }) {
                Button { addingTracks = true } label: { Label("Добавить треки", systemImage: "plus").font(PulseTheme.body(14, weight: .semibold)).padding(.horizontal, 16).padding(.vertical, 12).background(PulseTheme.raised, in: Capsule()) }.buttonStyle(PulseTactileButton()).disabled(!store.signedIn)
            }
            Button("Изменить обложку") { chooseCover(item.id) }.font(PulseTheme.body(12)).foregroundStyle(PulseTheme.muted).buttonStyle(PulseTactileButton())
        }
    }
    private var infoTextAlignment: TextAlignment {
        #if os(macOS)
        return .leading
        #else
        return .center
        #endif
    }
    private var infoAlignment: HorizontalAlignment {
        #if os(macOS)
        return .leading
        #else
        return .center
        #endif
    }
    private var creationMenu: some View {
        Menu {
            Button("Новый плейлист") { creating = true }
            Button("Подобрать с ИИ") { showingAI = true }
        } label: {
            Image(systemName: "plus").frame(width: 42, height: 42).background(PulseTheme.raised, in: Circle())
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .frame(width: 42, height: 42)
        #if os(macOS)
        .menuStyle(.borderlessButton)
        #endif
        .accessibilityLabel("Создать плейлист")
    }
    private func chooseCover(_ id: String) { coverTarget = id; choosingCover = true }
}


private struct PulsePlaylistCreateSheet: View {
    @ObservedObject var store: PulseStore
    let created: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var cover: String?
    @State private var choosingCover = false
    @State private var encoding = false
    @State private var saving = false
    @State private var message: String?
    @State private var coverTask: Task<Void, Never>?
    #if os(iOS)
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoRequest = UUID()
    #endif
    @FocusState private var nameFocused: Bool
    private var canCreate: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !saving && !encoding && store.signedIn }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    Text("Новый плейлист").font(PulseTheme.display(28)).multilineTextAlignment(.center)
                    Button { nameFocused = false; choosingCover = true } label: {
                        PulsePlaylistCover(cover: cover, size: 172, symbol: "camera.fill")
                            .overlay(alignment: .bottomTrailing) { Image(systemName: "plus").font(PulseTheme.body(14, weight: .bold)).padding(10).background(PulseTheme.accent, in: Circle()).foregroundStyle(PulseTheme.background).padding(10) }
                    }.buttonStyle(PulseTactileButton()).accessibilityLabel(cover == nil ? "Выбрать обложку плейлиста" : "Заменить обложку плейлиста").disabled(saving || encoding)
                    if encoding { ProgressView("Подготавливаем фото…").font(PulseTheme.body(13)) }
                    else if cover != nil { Button("Убрать фото") { cover = nil }.font(PulseTheme.body(13)).foregroundStyle(PulseTheme.muted).buttonStyle(PulseTactileButton()).disabled(saving) }
                    else { Text("Выбери свою обложку").font(PulseTheme.body(13)).foregroundStyle(PulseTheme.muted) }
                    TextField("Название плейлиста", text: $name).font(PulseTheme.body(17)).textFieldStyle(.plain).padding(18).background(PulseTheme.panel, in: RoundedRectangle(cornerRadius: 16)).focused($nameFocused).disabled(saving)
                        .onChange(of: name) { _, value in if value.count > 100 { name = String(value.prefix(100)) } }
                        #if os(iOS)
                        .submitLabel(.done)
                        #endif
                        .onSubmit { if canCreate { save() } }
                    if let message { Text(message).font(PulseTheme.body(13)).foregroundStyle(PulseTheme.accent).multilineTextAlignment(.center).accessibilityAddTraits(.updatesFrequently) }
                    Button(action: save) {
                        HStack(spacing: 10) { if saving { ProgressView().controlSize(.small) }; Text(saving ? "Создаём…" : "Создать плейлист") }.frame(maxWidth: .infinity)
                    }.buttonStyle(PulsePrimaryButton()).disabled(!canCreate)
                }.padding(26)
            }.background(PulseTheme.background)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() }.disabled(saving) } }
        }
        .interactiveDismissDisabled(saving)
        #if os(iOS)
        .photosPicker(isPresented: $choosingCover, selection: $selectedPhoto, matching: .images)
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            let request = UUID(); photoRequest = request
            coverTask?.cancel()
            coverTask = Task { await importPhoto(item, request: request) }
        }
        #else
        .fileImporter(isPresented: $choosingCover, allowedContentTypes: [.image]) { result in
            if case .success(let url) = result { coverTask = Task { await importCover(url) } }
        }
        #endif
        .onDisappear { coverTask?.cancel() }
        #if os(macOS)
        .frame(width: 480, height: 570)
        #endif
    }
    #if os(iOS)
    @MainActor private func importPhoto(_ item: PhotosPickerItem, request: UUID) async {
        encoding = true; message = nil; nameFocused = false
        defer { if photoRequest == request { encoding = false; selectedPhoto = nil } }
        do {
            guard let original = try await item.loadTransferable(type: Data.self) else { throw URLError(.cannotDecodeContentData) }
            try Task.checkCancellation()
            guard original.count <= 25 * 1024 * 1024 else { throw PulseAPIError(status: 413, message: "Выбери фото до 25 МБ") }
            let data = try await Task.detached(priority: .userInitiated) { try PulseCoverCodec.encode(original) }.value
            guard !Task.isCancelled, photoRequest == request else { return }
            cover = "data:image/jpeg;base64," + data.base64EncodedString()
        } catch { if !Task.isCancelled, photoRequest == request { message = error.localizedDescription } }
    }
    #endif
    @MainActor private func importCover(_ url: URL) async {
        encoding = true; message = nil
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() }; encoding = false }
        do {
            let data = try await Task.detached(priority: .userInitiated) { try PulseCoverCodec.encode(url) }.value
            guard !Task.isCancelled else { return }
            cover = "data:image/jpeg;base64," + data.base64EncodedString()
        } catch { if !Task.isCancelled { message = error.localizedDescription } }
    }
    private func save() {
        guard canCreate else { return }
        saving = true; message = nil; nameFocused = false
        Task {
            do { let id = try await store.createPlaylistWithCover(name, cover: cover); created(id); dismiss() }
            catch is CancellationError { saving = false }
            catch { message = error.localizedDescription; saving = false }
        }
    }
}

private struct PulsePlaylistTrackPicker: View {
    @ObservedObject var store: PulseStore
    let playlistID: String
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var pending = Set<String>()
    @State private var message: String?
    private var playlist: PulsePlaylist? { store.state.playlists.first { $0.id == playlistID } }
    private var results: [PulseTrack] { store.tracks.filter { PulseSearch.matches($0.title + " " + $0.artist + " " + ($0.album ?? ""), query: query) } }
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Добавить треки").font(PulseTheme.display(27))
                        Text(playlist?.name ?? "Плейлист недоступен").font(PulseTheme.body(14)).foregroundStyle(PulseTheme.muted).lineLimit(2)
                    }
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass").foregroundStyle(PulseTheme.accent)
                        TextField("Трек или исполнитель", text: $query).font(PulseTheme.body(16)).textFieldStyle(.plain)
                            #if os(iOS)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.search)
                            #endif
                        if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(PulseTactileButton()).accessibilityLabel("Очистить поиск") }
                    }.padding(16).background(PulseTheme.panel, in: RoundedRectangle(cornerRadius: 16))
                    if let message { Text(message).font(PulseTheme.body(13)).foregroundStyle(PulseTheme.accent) }
                    if playlist == nil { ContentUnavailableView("Плейлист недоступен", systemImage: "music.note.list", description: Text("Вернись к списку плейлистов.")) }
                    else if results.isEmpty { ContentUnavailableView("Ничего не найдено", systemImage: "magnifyingglass", description: Text("Попробуй другое название или имя исполнителя.")) }
                    else { ForEach(results) { track in pickerRow(track) } }
                }.padding(24)
            }.background(PulseTheme.background)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        #else
        .frame(width: 620, height: 720)
        #endif
    }
    private func pickerRow(_ track: PulseTrack) -> some View {
        let added = playlist?.tracks.contains(track.id) == true
        let busy = pending.contains(track.id)
        return HStack(spacing: 12) {
            PulseArtworkView(track: track, size: 48, radius: 11)
            VStack(alignment: .leading, spacing: 5) {
                Text(track.title).font(PulseTheme.body(15, weight: .medium)).lineLimit(1)
                Text(track.artist).font(PulseTheme.body(13)).foregroundStyle(PulseTheme.muted).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button { add(track) } label: {
                Group {
                    if busy { ProgressView().controlSize(.small) }
                    else if added { Label("Добавлено", systemImage: "checkmark").font(PulseTheme.body(11, weight: .medium)) }
                    else { Image(systemName: "plus").font(PulseTheme.body(18, weight: .semibold)) }
                }.frame(width: added ? 104 : 44, height: 44)
                    .background(added ? PulseTheme.accent.opacity(0.12) : PulseTheme.raised, in: Capsule()).foregroundStyle(added ? PulseTheme.accent : PulseTheme.text)
            }.buttonStyle(PulseTactileButton()).disabled(added || busy || playlist == nil || !store.signedIn)
                .accessibilityLabel(added ? "Добавлено: \(track.title)" : "Добавить: \(track.title)")
                .help(added ? "Добавлено" : "Добавить в плейлист")
        }.padding(.vertical, 2)
    }
    private func add(_ track: PulseTrack) {
        guard !pending.contains(track.id) else { return }
        pending.insert(track.id); message = nil
        Task {
            defer { pending.remove(track.id) }
            do { try await store.addTrack(track, toPlaylistID: playlistID) }
            catch is CancellationError { }
            catch { message = error.localizedDescription }
        }
    }
}

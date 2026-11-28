import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import PhotosUI
import UIKit
#else
import AppKit
#endif

struct PulsePlaylistItem: Identifiable {
    let id: String, name: String, symbol: String
    let tracks: [PulseTrack]
    let cover: String?
    @MainActor static func all(store: PulseStore) -> [PulsePlaylistItem] {
        (store.downloads.isOffline ? [PulsePlaylistItem(id: "offline", name: "Офлайн", symbol: "wifi.slash", tracks: store.downloads.offlineTracks, cover: nil)] : []) + [PulsePlaylistItem(id: "liked", name: "Понравилось", symbol: "heart.fill", tracks: PulseLibrary.ordered(store.state.liked, in: store.tracks), cover: store.state.playlistCovers["liked"]),
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
    @State private var renaming: PulsePlaylistRenameTarget?
    @State private var editing = false
    @State private var editMessage: String?
    @State private var editGeneration = UUID()
    @StateObject private var reorder = PulsePlaylistReorderDraft()
    private var items: [PulsePlaylistItem] { PulsePlaylistItem.all(store: store) }
    private var item: PulsePlaylistItem? { items.first { $0.id == selected } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let item {
                    Button { selected = nil } label: { Label("Плейлисты", systemImage: "chevron.left") }.buttonStyle(PulseTactileButton())
                    playlistHeader(item)
                    if item.tracks.isEmpty { Text("Здесь пока нет треков").foregroundStyle(PulseTheme.muted).frame(maxWidth: .infinity).padding(30) }
                    if editing { HStack(spacing: 10) { ProgressView().controlSize(.small); Text("Сохраняем плейлист…").font(PulseTheme.body(13)).foregroundStyle(PulseTheme.muted) } }
                    if let editMessage { Text(editMessage).font(PulseTheme.body(13)).foregroundStyle(PulseTheme.accent) }
                    playlistTracks(item)
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
                            }.buttonStyle(PulseTactileButton()).contextMenu {
                                if item.id != "offline" { Button("Изменить обложку", systemImage: "photo") { chooseCover(item.id) } }
                                Button("Скачать все треки", systemImage: "arrow.down.circle") { store.downloads.downloadAll(item.tracks) }.disabled(item.tracks.isEmpty)
                                if isEditable(item.id) { Button("Переименовать", systemImage: "pencil") { renaming = PulsePlaylistRenameTarget(id: item.id, name: item.name) } }
                            }
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
        .sheet(item: $renaming) { target in PulsePlaylistRenameSheet(store: store, target: target).preferredColorScheme(.dark).tint(PulseTheme.accent) }
        .onChange(of: store.user?.id) { _, _ in creating = false; addingTracks = false; renaming = nil; resetEditing() }
        .onChange(of: selected) { _, _ in resetEditing() }
        .onChange(of: store.downloads.isOffline) { _, offline in if !offline && selected == "offline" { selected = nil } }
        .onChange(of: item?.tracks.map(\.id)) { _, ids in
            if let track = reorder.active?.track, ids?.contains(track) != true { reorder.reset() }
        }
        .onDisappear { resetEditing() }
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
        Button { if item.id != "offline" { chooseCover(item.id) } } label: {
            PulsePlaylistCover(cover: item.cover, size: 208, symbol: item.symbol, fallback: item.tracks.first)
        }.buttonStyle(PulseTactileButton()).disabled(item.id == "offline").accessibilityLabel(item.id == "offline" ? "Обложка офлайн-плейлиста" : "Изменить обложку плейлиста")
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
            PulsePlaylistDownloadButton(tracks: item.tracks, downloads: store.downloads)
            if store.state.playlists.contains(where: { $0.id == item.id }) {
                HStack(spacing: 12) {
                    Button { addingTracks = true } label: { Label("Добавить треки", systemImage: "plus").font(PulseTheme.body(14, weight: .semibold)).padding(.horizontal, 16).padding(.vertical, 12).background(PulseTheme.raised, in: Capsule()) }.buttonStyle(PulseTactileButton()).disabled(!store.signedIn || editing)
                    Menu {
                        Button("Переименовать", systemImage: "pencil") { renaming = PulsePlaylistRenameTarget(id: item.id, name: item.name) }
                        Button("Изменить обложку", systemImage: "photo") { chooseCover(item.id) }
                    } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44).background(PulseTheme.raised, in: Circle()) }
                        .menuIndicator(.hidden)
                        #if os(macOS)
                        .menuStyle(.borderlessButton)
                        #endif
                        .fixedSize().disabled(editing).accessibilityLabel("Настройки плейлиста")
                }
            }
            if item.id != "offline" && !isEditable(item.id) { Button("Изменить обложку") { chooseCover(item.id) }.font(PulseTheme.body(12)).foregroundStyle(PulseTheme.muted).buttonStyle(PulseTactileButton()) }
        }
    }
    private func isEditable(_ id: String) -> Bool { store.signedIn && store.state.playlists.contains { $0.id == id } }
    private func displayTracks(_ item: PulsePlaylistItem) -> [PulseTrack] {
        guard reorder.playlistID == item.id, let draft = reorder.draft else { return item.tracks }
        let tracks = Dictionary(item.tracks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return draft.compactMap { tracks[$0] } + item.tracks.filter { !draft.contains($0.id) }
    }
    @ViewBuilder private func playlistTracks(_ item: PulsePlaylistItem) -> some View {
        if isEditable(item.id) {
            LazyVStack(spacing: 0) {
                ForEach(Array(displayTracks(item).enumerated()), id: \.element.id) { index, track in
                    editableRow(track, index: index, item: item)
                        .onDrop(of: [UTType.text.identifier], delegate: PulsePlaylistDropTarget(reorder: reorder, playlistID: item.id, owner: store.user?.id ?? "", target: track.id, commit: commitDrop))
                    Divider().overlay(PulseTheme.line)
                }
                if !item.tracks.isEmpty {
                    HStack { Image(systemName: "arrow.down"); Text(reorder.active == nil ? "Перетаскивай треки за ручку справа" : "Переместить в конец") }.font(PulseTheme.body(12)).foregroundStyle(PulseTheme.muted).frame(maxWidth: .infinity, minHeight: 48).contentShape(Rectangle())
                        .onDrop(of: [UTType.text.identifier], delegate: PulsePlaylistDropTarget(reorder: reorder, playlistID: item.id, owner: store.user?.id ?? "", target: nil, commit: commitDrop))
                }
            }.animation(reducedMotion ? nil : .easeInOut(duration: 0.16), value: reorder.draft)
        } else {
            LazyVStack(spacing: 0) { ForEach(Array(item.tracks.enumerated()), id: \.element.id) { index, track in PulseTrackRow(track: track, index: index + 1) { store.play(track, within: item.tracks) }; Divider().overlay(PulseTheme.line) } }
        }
    }
    private func editableRow(_ track: PulseTrack, index: Int, item: PulsePlaylistItem) -> some View {
        HStack(spacing: 8) {
            Button { store.play(track, within: item.tracks) } label: {
                HStack(spacing: 12) {
                    PulseArtworkView(track: track, size: 46, radius: 11)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(track.title).font(PulseTheme.body(15, weight: .medium)).foregroundStyle(store.currentID == track.id ? PulseTheme.accent : PulseTheme.text).lineLimit(1)
                        Text(track.artist).font(PulseTheme.body(13)).foregroundStyle(PulseTheme.muted).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.contentShape(Rectangle())
            }.buttonStyle(PulseTactileButton()).accessibilityLabel("Воспроизвести \(track.title), \(track.artist)")
            Menu {
                Button("Поднять выше", systemImage: "arrow.up") { moveByStep(track, item: item, direction: -1) }.disabled(index == 0)
                Button("Опустить ниже", systemImage: "arrow.down") { moveByStep(track, item: item, direction: 1) }.disabled(index == item.tracks.count - 1)
                Button("Убрать из плейлиста", systemImage: "minus.circle", role: .destructive) { remove(track, item: item) }
                Divider()
                PulseTrackActions(track: track)
            } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44).foregroundStyle(PulseTheme.muted) }
                .menuIndicator(.hidden)
                #if os(macOS)
                .menuStyle(.borderlessButton)
                #endif
                .fixedSize().disabled(editing || reorder.active != nil).accessibilityLabel("Действия с треком в плейлисте")
            PulsePlaylistDragHandle(enabled: !editing, begin: {
                guard selected == item.id, let owner = store.user?.id else { return nil }
                return reorder.begin(playlistID: item.id, track: track.id, ids: item.tracks.map(\.id), owner: owner)
            }, ended: { token in reorder.cancel(token) })
            .frame(width: 44, height: 44).accessibilityLabel("Изменить порядок: \(track.title)")
            .accessibilityAction(named: "Поднять выше") { moveByStep(track, item: item, direction: -1) }
            .accessibilityAction(named: "Опустить ниже") { moveByStep(track, item: item, direction: 1) }
            .help("Перетащи, чтобы изменить порядок")
        }.padding(.vertical, 9).padding(.horizontal, 4)
            .background(reorder.active?.track == track.id ? PulseTheme.accent.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 12))
    }
    private func resetEditing() { editGeneration = UUID(); editing = false; editMessage = nil; reorder.reset() }
    private func remove(_ track: PulseTrack, item: PulsePlaylistItem) {
        performEdit(playlistID: item.id) { try await store.removeTrack(track.id, fromPlaylistID: item.id) }
    }
    private func moveByStep(_ track: PulseTrack, item: PulsePlaylistItem, direction: Int) {
        guard let index = item.tracks.firstIndex(where: { $0.id == track.id }) else { return }
        let ids = item.tracks.map(\.id)
        if direction < 0, index > 0 { performMove(track: track.id, playlistID: item.id, before: ids[index - 1]) }
        else if direction > 0, index + 1 < ids.count { performMove(track: track.id, playlistID: item.id, before: index + 2 < ids.count ? ids[index + 2] : nil) }
    }
    private func commitDrop(_ move: PulsePlaylistDragMove) { performMove(track: move.track, playlistID: move.playlistID, before: move.before, dragToken: move.token) }
    private func performMove(track: String, playlistID: String, before: String?, dragToken: UUID? = nil) {
        performEdit(playlistID: playlistID, dragToken: dragToken) { try await store.moveTrack(track, inPlaylistID: playlistID, before: before) }
    }
    private func performEdit(playlistID: String, dragToken: UUID? = nil, operation: @escaping () async throws -> Void) {
        guard !editing, selected == playlistID, let owner = store.user?.id else { if let dragToken { reorder.complete(dragToken) }; return }
        let generation = editGeneration
        editing = true; editMessage = nil
        Task {
            do { try await operation() }
            catch is CancellationError { }
            catch { if editGeneration == generation, selected == playlistID, store.user?.id == owner { editMessage = error.localizedDescription } }
            guard editGeneration == generation, selected == playlistID, store.user?.id == owner else { return }
            editing = false
            if let dragToken { reorder.complete(dragToken) }
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
    private func chooseCover(_ id: String) { guard id != "offline" else { return }; coverTarget = id; choosingCover = true }
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
    @StateObject private var preview: PulseTrackPreview
    @Environment(\.scenePhase) private var scenePhase
    init(store: PulseStore, playlistID: String) {
        self.store = store; self.playlistID = playlistID
        _preview = StateObject(wrappedValue: PulseTrackPreview(store: store))
    }
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
                    if let error = preview.error { Text(error).font(PulseTheme.body(13)).foregroundStyle(PulseTheme.muted).accessibilityAddTraits(.updatesFrequently) }
                    if playlist == nil { ContentUnavailableView("Плейлист недоступен", systemImage: "music.note.list", description: Text("Вернись к списку плейлистов.")) }
                    else if results.isEmpty { ContentUnavailableView("Ничего не найдено", systemImage: "magnifyingglass", description: Text("Попробуй другое название или имя исполнителя.")) }
                    else { ForEach(results) { track in pickerRow(track) } }
                }.padding(24)
            }.background(PulseTheme.background)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
        .onDisappear { preview.stop() }
        .onChange(of: query) { _, _ in preview.stop() }
        .onChange(of: store.user?.id) { _, _ in preview.stop(resume: false) }
        .onChange(of: scenePhase) { _, phase in if phase != .active { preview.stop(resume: false) } }
        .onChange(of: store.tracks.map(\.id)) { _, ids in if let id = preview.trackID, !ids.contains(id) { preview.stop() } }
        .onChange(of: playlist?.id) { _, id in if id == nil { preview.stop() } }
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
            Button { preview.toggle(track) } label: {
                HStack(spacing: 12) {
                    PulseArtworkView(track: track, size: 48, radius: 11)
                        .overlay {
                            RoundedRectangle(cornerRadius: 11).fill(.black.opacity(preview.trackID == track.id ? 0.48 : 0.18))
                            if preview.trackID == track.id && preview.loading { ProgressView().controlSize(.small).tint(.white) }
                            else { Image(systemName: preview.trackID == track.id && preview.playing ? "pause.fill" : "play.fill").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white) }
                        }
                    VStack(alignment: .leading, spacing: 5) {
                        Text(track.title).font(PulseTheme.body(15, weight: .medium)).foregroundStyle(preview.trackID == track.id ? PulseTheme.accent : PulseTheme.text).lineLimit(1)
                        Text(preview.trackID == track.id ? (preview.loading ? "Загружаем отрывок…" : "Отрывок из середины") : track.artist).font(PulseTheme.body(13)).foregroundStyle(PulseTheme.muted).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.contentShape(Rectangle())
            }.buttonStyle(PulseTactileButton()).disabled(playlist == nil)
                .accessibilityLabel(preview.trackID == track.id ? "Остановить отрывок: \(track.title)" : "Прослушать отрывок: \(track.title), \(track.artist)")
                .help("Прослушать отрывок из середины")
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

private struct PulsePlaylistRenameTarget: Identifiable {
    let id: String
    let name: String
}
private struct PulsePlaylistRenameSheet: View {
    @ObservedObject var store: PulseStore
    let target: PulsePlaylistRenameTarget
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var saving = false
    @State private var message: String?
    @FocusState private var focused: Bool
    init(store: PulseStore, target: PulsePlaylistRenameTarget) { self.store = store; self.target = target; _name = State(initialValue: target.name) }
    private var valid: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !saving && store.signedIn }
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                Text("Название плейлиста").font(PulseTheme.display(25))
                TextField("Название", text: $name).font(PulseTheme.body(17)).textFieldStyle(.plain).padding(18).background(PulseTheme.panel, in: RoundedRectangle(cornerRadius: 16)).focused($focused).disabled(saving)
                    .onChange(of: name) { _, value in if value.count > 100 { name = String(value.prefix(100)) } }
                    .onSubmit { if valid { save() } }
                if let message { Text(message).font(PulseTheme.body(13)).foregroundStyle(PulseTheme.accent) }
                Button(action: save) { HStack { if saving { ProgressView().controlSize(.small) }; Text(saving ? "Сохраняем…" : "Сохранить") }.frame(maxWidth: .infinity) }.buttonStyle(PulsePrimaryButton()).disabled(!valid)
                Spacer(minLength: 0)
            }.padding(26).background(PulseTheme.background)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() }.disabled(saving) } }
        }.interactiveDismissDisabled(saving)
            .onAppear { focused = true }
        #if os(macOS)
        .frame(width: 480, height: 330)
        #else
        .presentationDetents([.medium])
        #endif
    }
    private func save() {
        guard valid else { return }
        saving = true; message = nil; focused = false
        Task {
            do { try await store.renamePlaylist(target.id, name: name); dismiss() }
            catch is CancellationError { saving = false }
            catch { message = error.localizedDescription; saving = false }
        }
    }
}

private struct PulsePlaylistDragMove {
    let playlistID: String
    let track: String
    let before: String?
    let token: UUID
}
private final class PulsePlaylistReorderDraft: ObservableObject {
    struct Active {
        let playlistID: String, track: String, owner: String
        let token: UUID
        let original: [String]
    }
    @Published private(set) var active: Active?
    @Published private(set) var draft: [String]?
    private(set) var playlistID: String?
    private var pendingToken: UUID?
    func begin(playlistID: String, track: String, ids: [String], owner: String) -> UUID? {
        guard active == nil, pendingToken == nil, ids.contains(track), !owner.isEmpty else { return nil }
        let token = UUID()
        self.playlistID = playlistID; draft = ids
        active = Active(playlistID: playlistID, track: track, owner: owner, token: token, original: ids)
        return token
    }
    func accepts(playlistID: String, owner: String) -> Bool { active?.playlistID == playlistID && active?.owner == owner }
    func hover(_ target: String?) {
        guard let active, var ids = draft, let source = ids.firstIndex(of: active.track), target != active.track else { return }
        if let target {
            guard let destination = ids.firstIndex(of: target) else { return }
            ids.remove(at: source)
            ids.insert(active.track, at: min(destination, ids.count))
        } else {
            ids.remove(at: source); ids.append(active.track)
        }
        if ids != draft { draft = ids }
    }
    func drop() -> PulsePlaylistDragMove? {
        guard let active, let ids = draft, let index = ids.firstIndex(of: active.track) else { reset(); return nil }
        guard ids != active.original else { reset(); return nil }
        let move = PulsePlaylistDragMove(playlistID: active.playlistID, track: active.track, before: index + 1 < ids.count ? ids[index + 1] : nil, token: active.token)
        pendingToken = active.token
        self.active = nil
        return move
    }
    func cancel(_ token: UUID) { if active?.token == token { reset() } }
    func complete(_ token: UUID) { if pendingToken == token { reset() } }
    func reset() { active = nil; draft = nil; playlistID = nil; pendingToken = nil }
}
private struct PulsePlaylistDropTarget: DropDelegate {
    let reorder: PulsePlaylistReorderDraft
    let playlistID: String
    let owner: String
    let target: String?
    let commit: (PulsePlaylistDragMove) -> Void
    func validateDrop(info: DropInfo) -> Bool { reorder.accepts(playlistID: playlistID, owner: owner) && info.hasItemsConforming(to: [UTType.text.identifier]) }
    func dropEntered(info: DropInfo) { if validateDrop(info: info) { reorder.hover(target) } }
    func dropUpdated(info: DropInfo) -> DropProposal? { validateDrop(info: info) ? DropProposal(operation: .move) : DropProposal(operation: .cancel) }
    func performDrop(info: DropInfo) -> Bool {
        guard validateDrop(info: info) else { return false }
        if let move = reorder.drop() { commit(move) }
        return true
    }
}

// Native source callbacks report cancelled drags as well as successful drops.
// Hover only adjusts the local draft; the drop delegate sends one cloud operation.
#if os(iOS)
private struct PulsePlaylistDragHandle: UIViewRepresentable {
    let enabled: Bool
    let begin: () -> UUID?
    let ended: (UUID) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(begin: begin, ended: ended) }
    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView(image: UIImage(systemName: "line.3.horizontal", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)))
        view.contentMode = .center; view.tintColor = .secondaryLabel; view.isUserInteractionEnabled = true
        let drag = UIDragInteraction(delegate: context.coordinator); drag.isEnabled = true
        view.addInteraction(drag)
        return view
    }
    func updateUIView(_ view: UIImageView, context: Context) { context.coordinator.enabled = enabled; context.coordinator.begin = begin; context.coordinator.ended = ended; view.alpha = enabled ? 1 : 0.4 }
    final class Coordinator: NSObject, UIDragInteractionDelegate {
        var enabled = true
        var begin: () -> UUID?
        var ended: (UUID) -> Void
        private var token: UUID?
        init(begin: @escaping () -> UUID?, ended: @escaping (UUID) -> Void) { self.begin = begin; self.ended = ended }
        func dragInteraction(_ interaction: UIDragInteraction, itemsForBeginning session: UIDragSession) -> [UIDragItem] {
            guard enabled, let token = begin() else { return [] }
            self.token = token
            return [UIDragItem(itemProvider: NSItemProvider(object: token.uuidString as NSString))]
        }
        func dragInteraction(_ interaction: UIDragInteraction, sessionAllowsMoveOperation session: UIDragSession) -> Bool { true }
        func dragInteraction(_ interaction: UIDragInteraction, sessionIsRestrictedToDraggingApplication session: UIDragSession) -> Bool { true }
        func dragInteraction(_ interaction: UIDragInteraction, session: UIDragSession, didEndWith operation: UIDropOperation) { if let token { ended(token) }; token = nil }
    }
}
#else
private struct PulsePlaylistDragHandle: NSViewRepresentable {
    let enabled: Bool
    let begin: () -> UUID?
    let ended: (UUID) -> Void
    func makeNSView(context: Context) -> PulsePlaylistDragNSView { PulsePlaylistDragNSView() }
    func updateNSView(_ view: PulsePlaylistDragNSView, context: Context) { view.enabled = enabled; view.begin = begin; view.ended = ended; view.needsDisplay = true }
}
private final class PulsePlaylistDragNSView: NSView, NSDraggingSource {
    override var mouseDownCanMoveWindow: Bool { false }
    var enabled = true
    var begin: (() -> UUID?)?
    var ended: ((UUID) -> Void)?
    private var token: UUID?
    override func draw(_ dirtyRect: NSRect) {
        NSColor.secondaryLabelColor.withAlphaComponent(enabled ? 1 : 0.4).setStroke()
        let path = NSBezierPath(); path.lineWidth = 1.8
        for offset in [-5.0, 0.0, 5.0] { path.move(to: NSPoint(x: bounds.midX - 8, y: bounds.midY + offset)); path.line(to: NSPoint(x: bounds.midX + 8, y: bounds.midY + offset)) }
        path.stroke()
    }
    override func mouseDown(with event: NSEvent) { }
    override func mouseDragged(with event: NSEvent) {
        guard enabled, token == nil, let token = begin?() else { return }
        self.token = token
        let data = NSPasteboardItem(); data.setString(token.uuidString, forType: .string)
        let item = NSDraggingItem(pasteboardWriter: data)
        item.setDraggingFrame(bounds, contents: NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: nil))
        beginDraggingSession(with: [item], event: event, source: self)
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { context == .withinApplication ? .move : [] }
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) { if let token { ended?(token) }; token = nil }
}
#endif

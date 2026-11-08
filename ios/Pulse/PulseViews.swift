import SwiftUI
import UniformTypeIdentifiers

struct PulseRootView: View {
    @EnvironmentObject private var store: PulseStore
    @State private var collection: PulseCollection? = .catalog
    @State private var query = ""
    @State private var showAccount = false
    @State private var importing = false
    @State private var newPlaylist = false
    @State private var playlistName = ""
    @State private var activePlaylist: String?
    private var selected: PulseCollection { collection ?? .catalog }
    private var visibleTracks: [PulseTrack] {
        let values: [PulseTrack]
        switch selected {
        case .catalog: values = store.tracks
        case .library: values = store.tracks.filter { store.ownedIDs.contains($0.id) }
        case .liked: values = PulseLibrary.ordered(store.state.liked, in: store.tracks)
        case .history: values = PulseLibrary.ordered(store.state.history.map(\.id), in: store.tracks)
        case .playlists:
            values = PulseLibrary.ordered(store.state.playlists.first { $0.id == activePlaylist }?.tracks ?? [], in: store.tracks)
        }
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? values : values.filter { ($0.title + " " + $0.artist + " " + ($0.album ?? "")).localizedCaseInsensitiveContains(text) }
    }
    var body: some View {
        NavigationSplitView {
            List(PulseCollection.allCases, selection: $collection) { item in
                Label(item.title, systemImage: item.symbol).tag(item)
            }
            .navigationTitle("Pulse")
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(store.user?.name ?? "Твоя музыка рядом").font(.headline)
                    Text(store.signedIn ? "Общий аккаунт с сайтом" : "Войди для синхронизации").font(.caption).foregroundStyle(.secondary)
                    Button(store.signedIn ? "Аккаунт" : "Войти") { showAccount = true }
                        .buttonStyle(.borderedProminent)
                }.padding().frame(maxWidth: .infinity, alignment: .leading)
            }
        } detail: {
            VStack(spacing: 0) {
                if selected == .playlists { playlistPicker }
                if !store.signedIn && selected != .catalog {
                    emptyState(symbol: "person.crop.circle", title: "Войди в свой аккаунт", detail: "Избранное, история и плейлисты появятся с сайта.")
                } else if visibleTracks.isEmpty {
                    emptyState(symbol: selected.symbol, title: query.isEmpty ? "Здесь пока тихо" : "Ничего не найдено", detail: query.isEmpty ? "Добавь музыку или выбери другую подборку." : "Попробуй другое название или исполнителя.")
                } else {
                    List(visibleTracks) { track in
                        PulseTrackRow(track: track, playing: track.id == store.currentID && !store.paused) {
                            store.play(track, within: visibleTracks)
                        }
                        .contextMenu {
                            Button(store.state.liked.contains(track.id) ? "Убрать из избранного" : "В избранное", systemImage: "heart") { store.like(track) }
                            if !store.state.playlists.isEmpty {
                                Menu("Добавить в плейлист") {
                                    ForEach(store.state.playlists) { playlist in
                                        Button(playlist.name) { store.add(track, to: playlist) }
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await store.refresh() }
                }
                syncStatus
            }
            .navigationTitle(selected == .playlists ? (store.state.playlists.first { $0.id == activePlaylist }?.name ?? selected.title) : selected.title)
            .searchable(text: $query, prompt: "Трек, исполнитель, альбом")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    if selected == .playlists {
                        Button { if store.signedIn { newPlaylist = true } else { showAccount = true } } label: { Image(systemName: "plus") }.help("Создать плейлист")
                    }
                    Button { Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise") }.disabled(store.syncing).help("Обновить медиатеку")
                    Button { if store.signedIn { importing = true } else { showAccount = true } } label: { Image(systemName: "square.and.arrow.up") }.disabled(store.uploading).help("Импортировать музыку")
                    Button { showAccount = true } label: { Image(systemName: store.signedIn ? "person.crop.circle.fill" : "person.crop.circle") }.help("Аккаунт")
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { PulsePlayerBar() }
        .sheet(isPresented: $showAccount) { PulseAccountView() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio, .data], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): Task { await store.importFiles(urls) }
            case .failure(let error): store.error = error.localizedDescription
            }
        }
        .alert("Новый плейлист", isPresented: $newPlaylist) {
            TextField("Название", text: $playlistName)
            Button("Создать") {
                let name = playlistName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { store.createPlaylist(name); playlistName = "" }
            }
            Button("Отмена", role: .cancel) { }
        }
        .alert("Pulse", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("Понятно") { store.error = nil }
        } message: { Text(store.error ?? "") }
    }
    private var playlistPicker: some View {
        HStack {
            Picker("Плейлист", selection: $activePlaylist) {
                Text("Выбери плейлист").tag(String?.none)
                ForEach(store.state.playlists) { Text($0.name).tag(Optional($0.id)) }
            }.labelsHidden()
            Spacer()
        }.padding()
    }
    private var syncStatus: some View {
        HStack(spacing: 6) {
            if store.syncing || store.uploading { ProgressView().controlSize(.small) }
            Text(store.uploading ? store.uploadStatus : store.syncing ? "Обновляем медиатеку…" : "\(visibleTracks.count) треков")
            Spacer()
            if let date = store.lastSync { Text(date, style: .time) }
        }.font(.caption).foregroundStyle(.secondary).padding(.horizontal).padding(.vertical, 8)
    }
    private func emptyState(symbol: String, title: String, detail: String) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: symbol).font(.system(size: 42)).foregroundStyle(.purple)
            Text(title).font(.title2.bold())
            Text(detail).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if !store.signedIn { Button("Войти") { showAccount = true }.buttonStyle(.borderedProminent) }
            Spacer()
        }.padding().frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PulseArtworkView: View {
    let track: PulseTrack?
    var size: CGFloat = 48
    var body: some View {
        AsyncImage(url: track?.artworkURL) { image in image.resizable().scaledToFill() } placeholder: {
            ZStack { LinearGradient(colors: [.indigo, .purple.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing); Image(systemName: "waveform").foregroundStyle(.white.opacity(0.8)) }
        }.frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.2))
    }
}
struct PulseTrackRow: View {
    @EnvironmentObject private var store: PulseStore
    let track: PulseTrack
    let playing: Bool
    let play: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Button(action: play) {
                HStack(spacing: 12) {
                    PulseArtworkView(track: track)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(track.title).font(.headline).foregroundStyle(playing ? Color.purple : Color.primary).lineLimit(1)
                        Text(track.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if playing { Image(systemName: "waveform").foregroundStyle(.purple) }
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Воспроизвести \(track.title), \(track.artist)")
            Button { store.like(track) } label: {
                Image(systemName: store.state.liked.contains(track.id) ? "heart.fill" : "heart")
                    .foregroundStyle(store.state.liked.contains(track.id) ? Color.pink : Color.secondary)
            }.buttonStyle(.borderless).accessibilityLabel("Избранное: \(track.title)")
        }.padding(.vertical, 5)
    }
}

struct PulsePlayerBar: View {
    @EnvironmentObject private var store: PulseStore
    @State private var seeking = false
    @State private var seekTime = 0.0
    var body: some View {
        VStack(spacing: 10) {
            if store.currentTrack != nil {
                Slider(value: Binding(get: { seeking ? seekTime : min(store.time, max(store.duration, 1)) }, set: { seekTime = $0 }), in: 0...max(store.duration, 1)) { editing in
                    seeking = editing
                    if editing { seekTime = store.time } else { store.seek(seekTime) }
                }.accessibilityLabel("Позиция воспроизведения")
            }
            HStack(spacing: 12) {
                PulseArtworkView(track: store.currentTrack, size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.currentTrack?.title ?? "Выбери трек").font(.headline).lineLimit(1)
                    Text(store.buffering ? "Загрузка…" : store.currentTrack?.artist ?? "Pulse").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Button { store.next(-1) } label: { Image(systemName: "backward.end.fill") }.accessibilityLabel("Предыдущий трек")
                Button { store.togglePlayback() } label: { Image(systemName: store.paused ? "play.fill" : "pause.fill").font(.title2).frame(width: 36, height: 36) }.accessibilityLabel(store.paused ? "Воспроизвести" : "Пауза")
                Button { store.next(1) } label: { Image(systemName: "forward.end.fill") }.accessibilityLabel("Следующий трек")
            }.buttonStyle(.plain).disabled(store.currentTrack == nil)
            #if os(macOS)
            HStack {
                Text(Self.clock(store.time) + " / " + Self.clock(store.duration)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                Toggle("DJ · плавный переход", isOn: $store.dj).toggleStyle(.switch).controlSize(.small)
                Image(systemName: "speaker.wave.2")
                Slider(value: $store.volume, in: 0...1).frame(width: 110).accessibilityLabel("Громкость")
            }
            #endif
        }.padding(.horizontal, 18).padding(.vertical, 12).background(.ultraThinMaterial)
    }
    private static func clock(_ value: Double) -> String {
        guard value.isFinite, value >= 0 else { return "0:00" }
        return String(format: "%d:%02d", Int(value) / 60, Int(value) % 60)
    }
}

struct PulseAccountView: View {
    @EnvironmentObject private var store: PulseStore
    @Environment(\.dismiss) private var dismiss
    @State private var register = false
    @State private var email = ""
    @State private var password = ""
    @State private var name = ""
    @State private var formError: String?
    var body: some View {
        NavigationStack {
            Form {
                if let user = store.user {
                    Section("Аккаунт") {
                        Text(user.name).font(.headline)
                        Text(user.email).foregroundStyle(.secondary)
                        Text("Тот же аккаунт, что на сайте. Музыка и плейлисты синхронизируются автоматически.").font(.callout)
                    }
                    Section("Воспроизведение") { Toggle("DJ · плавные переходы", isOn: $store.dj) }
                    if !store.uploadStatus.isEmpty { Section("Импорт") { Text(store.uploadStatus) } }
                    Section {
                        Button("Обновить медиатеку") { Task { await store.refresh() } }
                        Button("Выйти из аккаунта", role: .destructive) { Task { await store.logout(); dismiss() } }.disabled(store.uploading)
                    }
                } else {
                    Section {
                        Picker("Аккаунт", selection: $register) { Text("Вход").tag(false); Text("Регистрация").tag(true) }.pickerStyle(.segmented)
                        if register { TextField("Имя", text: $name) }
                        TextField("Email", text: $email)
                            #if os(iOS)
                            .textInputAutocapitalization(.never).keyboardType(.emailAddress)
                            #endif
                        SecureField("Пароль · от 8 символов", text: $password)
                        Text("Используй email и пароль от сайта Pulse.").font(.caption).foregroundStyle(.secondary)
                        if let formError { Text(formError).foregroundStyle(.red) }
                        Button {
                            Task {
                                let success = await store.signIn(email: email, password: password, name: name, register: register)
                                if success { password = ""; dismiss() }
                                else { formError = store.error; store.error = nil }
                            }
                        } label: {
                            HStack { if store.authenticating { ProgressView().controlSize(.small) }; Text(register ? "Создать аккаунт" : "Войти") }
                        }.disabled(store.authenticating || password.count < 8 || !email.contains("@"))
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(store.signedIn ? "Мой Pulse" : "Добро пожаловать")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
        #if os(macOS)
        .frame(width: 480, height: 520)
        #endif
    }
}

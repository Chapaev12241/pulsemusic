import SwiftUI
import UniformTypeIdentifiers

struct PulseRootView: View {
    @EnvironmentObject private var store: PulseStore
    @State private var collection: PulseCollection = .home
    @State private var query = ""
    @State private var showAccount = false
    @State private var importing = false
    @State private var newPlaylist = false
    @State private var playlistName = ""
    @State private var activePlaylist: String?
    private var visibleTracks: [PulseTrack] {
        let values: [PulseTrack]
        switch collection {
        case .home, .catalog: values = store.tracks
        case .library: values = store.tracks.filter { store.ownedIDs.contains($0.id) }
        case .liked: values = PulseLibrary.ordered(store.state.liked, in: store.tracks)
        case .history: values = PulseLibrary.ordered(store.state.history.map(\.id), in: store.tracks)
        case .playlists: values = PulseLibrary.ordered(store.state.playlists.first { $0.id == activePlaylist }?.tracks ?? [], in: store.tracks)
        }
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? values : values.filter { ($0.title + " " + $0.artist + " " + ($0.album ?? "")).localizedCaseInsensitiveContains(text) }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                #if os(macOS)
                sidebar.frame(width: 224)
                Rectangle().fill(PulseTheme.line).frame(width: 1)
                #endif
                VStack(spacing: 0) {
                    header
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 26) {
                            if collection == .home && query.isEmpty {
                                PulseHomeView(select: select, play: { items in if let first = items.first { store.play(first, within: items) } })
                            } else {
                                collectionHeader
                                if collection == .playlists { playlistPicker }
                                if visibleTracks.isEmpty { emptyState }
                                else { trackList }
                            }
                            syncStatus
                        }
                        .padding(.horizontal, contentPadding).padding(.top, 10).padding(.bottom, 24)
                    }
                    .refreshable { await store.refresh() }
                }
            }
            Rectangle().fill(PulseTheme.line).frame(height: 1)
            PulsePlayerBar(store: store)
            #if os(iOS)
            mobileNavigation
            #endif
        }
        .background(PulseTheme.background).foregroundStyle(Color(red: 0.95, green: 0.94, blue: 0.94))
        #if os(macOS)
        .frame(minWidth: 840, minHeight: 580)
        #endif
        .sheet(isPresented: $showAccount) { PulseAccountView().environmentObject(store).tint(PulseTheme.accent).preferredColorScheme(.dark) }
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
        .onChange(of: query) { _, value in if !value.isEmpty && collection == .home { collection = .catalog } }
    }
    private var contentPadding: CGFloat {
        #if os(macOS)
        return 32
        #else
        return 18
        #endif
    }
    private func select(_ next: PulseCollection) { collection = next; query = "" }
    private func importMusic() { if store.signedIn { importing = true } else { showAccount = true } }
    private var header: some View {
        HStack(spacing: 12) {
            #if os(iOS)
            Text("Pulse").font(PulseTheme.heading(32))
            #endif
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(PulseTheme.muted)
                TextField("Трек, исполнитель, альбом", text: $query).textFieldStyle(.plain).font(.system(size: 13))
                    #if os(iOS)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    #endif
                if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(PulseTheme.muted) }
            }
            .padding(.horizontal, 14).frame(height: 46).background(PulseTheme.panel, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(PulseTheme.line))
            Button { Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(PulseIconButton()).disabled(store.syncing).help("Обновить медиатеку")
            Button { showAccount = true } label: {
                ZStack {
                    Circle().fill(PulseTheme.accent.opacity(0.2))
                    if let user = store.user { Text(String(user.name.prefix(1)).uppercased()).font(.system(size: 16, weight: .semibold)).foregroundStyle(PulseTheme.accent) }
                    else { Image(systemName: "person").foregroundStyle(PulseTheme.accent) }
                }.frame(width: 40, height: 40)
            }.buttonStyle(.plain).accessibilityLabel("Аккаунт")
        }.padding(.horizontal, contentPadding).padding(.vertical, 20)
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 28) {
            Text("Pulse").font(PulseTheme.heading(46)).padding(.horizontal, 14).padding(.top, 14)
            VStack(spacing: 6) {
                ForEach(PulseCollection.allCases) { item in
                    Button { select(item) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.symbol).font(.system(size: 17)).frame(width: 22)
                            Text(item.title).font(.system(size: 13, weight: collection == item ? .semibold : .regular))
                            Spacer()
                            if item == .liked && !store.state.liked.isEmpty { Text("\(store.state.liked.count)").font(.caption2).foregroundStyle(PulseTheme.muted) }
                        }
                        .foregroundStyle(collection == item ? Color.white : PulseTheme.muted).padding(.horizontal, 14).frame(height: 45)
                        .background(collection == item ? PulseTheme.raised : .clear, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(alignment: .leading) { if collection == item { Capsule().fill(PulseTheme.accent).frame(width: 3, height: 18) } }
                    }.buttonStyle(.plain)
                }
            }
            Spacer(minLength: 20)
            VStack(alignment: .leading, spacing: 12) {
                Button(action: importMusic) { Label(store.uploading ? "Загружаем…" : "Добавить музыку", systemImage: "plus").frame(maxWidth: .infinity) }.buttonStyle(PulsePrimaryButton()).disabled(store.uploading)
                HStack(spacing: 8) {
                    Image(systemName: "cloud").foregroundStyle(PulseTheme.accent)
                    Text("Одна музыка. Все устройства.").font(.system(size: 10)).foregroundStyle(PulseTheme.muted)
                }
            }.padding(.horizontal, 8)
            Button { showAccount = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "person.crop.circle").font(.title2).foregroundStyle(PulseTheme.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(store.user?.name ?? "Войти в Pulse").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                        Text(store.signedIn ? "Аккаунт синхронизирован" : "Сохрани свой вайб").font(.system(size: 10)).foregroundStyle(PulseTheme.muted)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(PulseTheme.muted)
                }.padding(12).background(PulseTheme.panel, in: RoundedRectangle(cornerRadius: 14))
            }.buttonStyle(.plain)
        }.padding(16)
    }
    private var mobileNavigation: some View {
        HStack(spacing: 0) {
            ForEach([PulseCollection.home, .catalog, .library, .liked, .playlists]) { item in
                Button { select(item) } label: {
                    VStack(spacing: 5) {
                        Image(systemName: item.symbol).font(.system(size: 19))
                        Text(item == .catalog ? "Поиск" : item.title).font(.system(size: 9))
                    }.frame(maxWidth: .infinity).frame(height: 52).foregroundStyle(collection == item ? PulseTheme.accent : PulseTheme.muted)
                }.buttonStyle(.plain)
            }
        }.padding(.horizontal, 6).padding(.top, 5).background(PulseTheme.background)
    }
    private var collectionHeader: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text(collection == .playlists ? (store.state.playlists.first { $0.id == activePlaylist }?.name ?? collection.title) : collection.title).font(PulseTheme.heading(40))
                Text(collection == .library ? "Твоя облачная коллекция — всегда рядом" : "\(visibleTracks.count) треков · твой следующий любимый уже здесь").font(.system(size: 12)).foregroundStyle(PulseTheme.muted)
            }
            Spacer()
            if collection == .playlists {
                Button { if store.signedIn { newPlaylist = true } else { showAccount = true } } label: { Image(systemName: "plus").frame(width: 38, height: 38) }.buttonStyle(.plain).background(PulseTheme.raised, in: RoundedRectangle(cornerRadius: 12))
            } else {
                Button(action: importMusic) { Image(systemName: "plus").frame(width: 38, height: 38) }.buttonStyle(.plain).background(PulseTheme.raised, in: RoundedRectangle(cornerRadius: 12)).accessibilityLabel("Добавить музыку")
            }
        }
    }
    private var playlistPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(store.state.playlists) { playlist in
                    Button { activePlaylist = playlist.id } label: {
                        Label(playlist.name, systemImage: "music.note.list").font(.system(size: 12)).padding(.horizontal, 15).padding(.vertical, 12)
                            .background(activePlaylist == playlist.id ? PulseTheme.accent.opacity(0.2) : PulseTheme.panel, in: Capsule())
                            .foregroundStyle(activePlaylist == playlist.id ? PulseTheme.accent : .white)
                    }.buttonStyle(.plain)
                }
            }
        }
    }
    private var trackList: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(visibleTracks.enumerated()), id: \.element.id) { index, track in
                PulseTrackRow(track: track, index: index + 1) { store.play(track, within: visibleTracks) }
                Rectangle().fill(PulseTheme.line).frame(height: 1).padding(.leading, 70)
            }
        }
    }
    private var emptyState: some View {
        VStack(spacing: 15) {
            Image(systemName: collection.symbol).font(.system(size: 40)).foregroundStyle(PulseTheme.accent)
            Text(!store.signedIn && collection != .catalog ? "Сохрани свою музыку" : "Пока ничего нет").font(.title3.bold())
            Text(!store.signedIn && collection != .catalog ? "Войди с аккаунтом сайта — и твоя медиатека будет здесь." : "Добавь треки или попробуй другой запрос.").font(.callout).foregroundStyle(PulseTheme.muted).multilineTextAlignment(.center)
            if !store.signedIn { Button("Войти в Pulse") { showAccount = true }.buttonStyle(PulsePrimaryButton()) }
        }.frame(maxWidth: .infinity).padding(.vertical, 64).padding(.horizontal, 24).background(PulseTheme.panel, in: RoundedRectangle(cornerRadius: 22))
    }
    private var syncStatus: some View {
        HStack(spacing: 7) {
            if store.syncing || store.uploading { ProgressView().controlSize(.small) }
            else { Circle().fill(PulseTheme.accent.opacity(0.8)).frame(width: 5, height: 5) }
            Text(store.uploading ? store.uploadStatus : store.syncing ? "Обновляем медиатеку…" : "Медиатека в облаке · \(store.tracks.count) треков")
            Spacer()
            if let date = store.lastSync { Text(date, style: .time) }
        }.font(.system(size: 10)).foregroundStyle(PulseTheme.muted)
    }
}

struct PulseHomeView: View {
    @EnvironmentObject private var store: PulseStore
    let select: (PulseCollection) -> Void
    let play: ([PulseTrack]) -> Void
    private var featured: [PulseTrack] {
        let favorites = Set(store.state.liked)
        let artists = Set(store.tracks.filter { favorites.contains($0.id) }.map(\.artist))
        return Array(store.tracks.sorted { (artists.contains($0.artist) ? 1 : 0) > (artists.contains($1.artist) ? 1 : 0) }.prefix(12))
    }
    private var artists: [(name: String, track: PulseTrack, count: Int)] {
        Dictionary(grouping: store.tracks, by: \.artist).map { (name: $0.key, track: $0.value[0], count: $0.value.count) }.sorted { $0.count > $1.count }.prefix(8).map { $0 }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            PulseHero(count: store.tracks.count) { play(featured.shuffled()) }
            sectionTitle("Твой следующий любимый", subtitle: "Знакомые чувства. Новое звучание.") { select(.catalog) }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(featured) { track in PulseTrackCard(track: track) { store.play(track, within: featured) } }
                }.padding(.bottom, 5)
            }.padding(.top, -14)
            if !artists.isEmpty {
                sectionTitle("В центре твоего вайба", subtitle: "Исполнители из коллекции") { select(.catalog) }
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 22) {
                        ForEach(artists, id: \.name) { artist in
                            Button { let list = store.tracks.filter { $0.artist == artist.name }; play(list) } label: {
                                VStack(spacing: 10) {
                                    PulseArtworkView(track: artist.track, size: 100, radius: 50)
                                    Text(artist.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                    Text("\(artist.count) треков").font(.system(size: 10)).foregroundStyle(PulseTheme.muted)
                                }.frame(width: 115)
                            }.buttonStyle(.plain)
                        }
                    }
                }.padding(.top, -12)
            }
            sectionTitle("Музыка всегда рядом", subtitle: "Выбирай трек и оставайся на своей волне") { select(.catalog) }
            LazyVStack(spacing: 0) {
                ForEach(Array(store.tracks.prefix(6).enumerated()), id: \.element.id) { index, track in
                    PulseTrackRow(track: track, index: index + 1) { store.play(track, within: store.tracks) }
                    Rectangle().fill(PulseTheme.line).frame(height: 1).padding(.leading, 70)
                }
            }.padding(.top, -18)
        }
    }
    private func sectionTitle(_ title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 20, weight: .semibold))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(PulseTheme.muted)
            }
            Spacer()
            Button(action: action) { Image(systemName: "arrow.up.right").font(.system(size: 15)).frame(width: 34, height: 34).background(PulseTheme.raised, in: Circle()) }.buttonStyle(.plain).accessibilityLabel("Вся музыка")
        }
    }
}

struct PulseHero: View {
    let count: Int
    let play: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 16) {
                Label("НА ТВОЕЙ ВОЛНЕ", systemImage: "sparkle").font(.system(size: 9, weight: .medium)).tracking(2).foregroundStyle(PulseTheme.accent)
                Text("Твоя музыка.\nТвой вайб.").font(PulseTheme.heading(titleSize)).lineSpacing(4).minimumScaleFactor(0.75).fixedSize(horizontal: false, vertical: true)
                Text("Момент — твой. Саундтрек — Pulse.").font(.system(size: 11)).foregroundStyle(PulseTheme.muted)
                Button(action: play) { Label("Запустить вайб", systemImage: "play.fill") }.buttonStyle(PulsePrimaryButton()).disabled(count == 0)
            }
            Spacer(minLength: 0)
            PulseVinyl().frame(width: vinylSize, height: vinylSize).rotationEffect(.degrees(-18)).accessibilityHidden(true)
        }
        .padding(heroPadding).frame(maxWidth: .infinity, minHeight: heroHeight, alignment: .leading)
        .background {
            ZStack {
                PulseTheme.panel
                RadialGradient(colors: [PulseTheme.accent.opacity(0.15), .clear], center: .topTrailing, startRadius: 0, endRadius: 380)
                LinearGradient(colors: [.clear, Color.blue.opacity(0.045)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 25)).overlay(RoundedRectangle(cornerRadius: 25).stroke(PulseTheme.line))
    }
    private var titleSize: CGFloat {
        #if os(macOS)
        return 61
        #else
        return 40
        #endif
    }
    private var vinylSize: CGFloat {
        #if os(macOS)
        return 190
        #else
        return 95
        #endif
    }
    private var heroPadding: CGFloat {
        #if os(macOS)
        return 36
        #else
        return 22
        #endif
    }
    private var heroHeight: CGFloat {
        #if os(macOS)
        return 285
        #else
        return 250
        #endif
    }
}
struct PulseVinyl: View {
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size.width
            ZStack {
                Circle().fill(Color(red: 0.055, green: 0.055, blue: 0.070))
                ForEach(0..<18) { ring in Circle().stroke(Color.white.opacity(ring % 3 == 0 ? 0.07 : 0.025), lineWidth: 1).padding(CGFloat(ring) * size / 48 + 4) }
                Circle().fill(PulseTheme.gradient).frame(width: size * 0.38, height: size * 0.38)
                Text("P").font(PulseTheme.heading(size * 0.29)).foregroundStyle(Color.black.opacity(0.85)).offset(y: size * 0.015)
            }.overlay(Circle().stroke(Color.white.opacity(0.08)))
        }
    }
}
struct PulseTrackCard: View {
    @EnvironmentObject private var store: PulseStore
    let track: PulseTrack
    let play: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: play) {
            VStack(alignment: .leading, spacing: 10) {
                PulseArtworkView(track: track, size: 150, radius: 12)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "play.fill").font(.system(size: 15)).foregroundStyle(.black).frame(width: 36, height: 36).background(PulseTheme.gradient, in: Circle()).padding(8).opacity(hover ? 1 : 0.8)
                    }
                Text(track.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text(track.artist).font(.system(size: 10)).foregroundStyle(PulseTheme.muted).lineLimit(1)
            }.frame(width: 150, alignment: .leading).padding(12).background(PulseTheme.panel, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(hover ? PulseTheme.accent.opacity(0.45) : PulseTheme.line))
        }.buttonStyle(.plain).onHover { hover = $0 }.contextMenu { PulseTrackActions(track: track) }
    }
}
struct PulseTrackRow: View {
    @EnvironmentObject private var store: PulseStore
    let track: PulseTrack
    let index: Int
    let play: () -> Void
    @State private var hover = false
    private var playing: Bool { store.currentID == track.id && !store.paused }
    var body: some View {
        HStack(spacing: 12) {
            #if os(macOS)
            Group {
                if playing { Image(systemName: "waveform").foregroundStyle(PulseTheme.accent) }
                else { Text(String(format: "%02d", index)).foregroundStyle(PulseTheme.muted) }
            }.font(.system(size: 11).monospacedDigit()).frame(width: 22)
            #endif
            Button(action: play) {
                HStack(spacing: 12) {
                    PulseArtworkView(track: track, size: 46, radius: 10)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(track.title).font(.system(size: 12, weight: .medium)).foregroundStyle(playing ? PulseTheme.accent : .white).lineLimit(1)
                        Text(track.artist).font(.system(size: 10)).foregroundStyle(PulseTheme.muted).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Воспроизвести \(track.title), \(track.artist)")
            #if os(macOS)
            Text(track.album ?? "").font(.system(size: 10)).foregroundStyle(PulseTheme.muted).lineLimit(1).frame(maxWidth: 180, alignment: .leading)
            #endif
            Button { store.like(track) } label: {
                Image(systemName: store.state.liked.contains(track.id) ? "heart.fill" : "heart").foregroundStyle(store.state.liked.contains(track.id) ? PulseTheme.accent : PulseTheme.muted).frame(width: 30, height: 40)
            }.buttonStyle(.plain).accessibilityLabel("Избранное: \(track.title)")
            Menu { PulseTrackActions(track: track) } label: { Image(systemName: "ellipsis").foregroundStyle(PulseTheme.muted).frame(width: 28, height: 40) }.fixedSize()
                #if os(macOS)
                .menuStyle(.borderlessButton)
                #endif
        }
        .padding(.horizontal, 10).padding(.vertical, 9).background(hover || playing ? PulseTheme.raised.opacity(0.7) : .clear, in: RoundedRectangle(cornerRadius: 12))
        .onHover { hover = $0 }.contextMenu { PulseTrackActions(track: track) }
    }
}
struct PulseTrackActions: View {
    @EnvironmentObject private var store: PulseStore
    let track: PulseTrack
    var body: some View {
        Button(store.state.liked.contains(track.id) ? "Убрать из избранного" : "В избранное", systemImage: "heart") { store.like(track) }
        if !store.state.playlists.isEmpty {
            Menu("Добавить в плейлист") { ForEach(store.state.playlists) { playlist in Button(playlist.name) { store.add(track, to: playlist) } } }
        }
    }
}

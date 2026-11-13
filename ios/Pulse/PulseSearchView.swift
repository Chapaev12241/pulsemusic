import SwiftUI

enum PulseSearch {
    static func key(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "ru_RU"))
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
    static func matches(_ text: String, query: String) -> Bool {
        let haystack = key(text)
        return key(query).split(separator: " ").allSatisfy { haystack.contains($0) }
    }
}

struct PulseSearchView: View {
    @ObservedObject var store: PulseStore
    @State private var query = ""
    @State private var artist: String?
    @FocusState private var focused: Bool
    private var artists: [String] {
        Array(Set(store.tracks.map(\.artist))).filter { !PulseSearch.key($0).isEmpty && PulseSearch.matches($0, query: query) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
    private var tracks: [PulseTrack] {
        if let artist { return store.tracks.filter { PulseSearch.key($0.artist) == PulseSearch.key(artist) } }
        return store.tracks.filter { PulseSearch.matches($0.title + " " + $0.artist + " " + ($0.album ?? ""), query: query) }
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if let artist {
                    Button { self.artist = nil } label: { Label("К результатам", systemImage: "chevron.left") }.buttonStyle(PulseTactileButton()).foregroundStyle(PulseTheme.accent)
                    HStack(spacing: 20) {
                        PulseArtworkView(track: tracks.first, size: 96, radius: 48)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(artist).font(PulseTheme.heading(36))
                            Text("Исполнитель · \(tracks.count) треков").font(.caption).foregroundStyle(PulseTheme.muted)
                        }
                    }
                    Button { if let first = tracks.first { store.play(first, within: tracks) } } label: { Label("Слушать", systemImage: "play.fill") }.buttonStyle(PulsePrimaryButton())
                } else {
                    Text("Найди свой звук.").font(PulseTheme.heading(40))
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass").foregroundStyle(PulseTheme.accent)
                        TextField("Трек, исполнитель, альбом", text: $query).textFieldStyle(.plain).focused($focused)
                            #if os(iOS)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.search)
                            #endif
                            .onSubmit { focused = false }
                        if !query.isEmpty { Button { query = ""; focused = true } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(PulseTactileButton()).accessibilityLabel("Очистить поиск") }
                    }.padding(16).pulseGlass(cornerRadius: 16)
                    if !artists.isEmpty {
                        Text(query.isEmpty ? "Исполнители" : "Найденные исполнители").font(.title3.bold())
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 18) {
                                ForEach(artists, id: \.self) { name in
                                    Button { focused = false; artist = name } label: {
                                        VStack(spacing: 10) {
                                            PulseArtworkView(track: store.tracks.first { $0.artist == name }, size: 88, radius: 44)
                                            Text(name).font(.system(size: 12, weight: .semibold)).lineLimit(2).multilineTextAlignment(.center)
                                        }.frame(width: 104)
                                    }.buttonStyle(PulseTactileButton()).accessibilityLabel("Исполнитель \(name)")
                                }
                            }.padding(.vertical, 4)
                        }
                    }
                }
                Text(artist != nil ? "Треки исполнителя" : query.isEmpty ? "Вся музыка" : "Треки · \(tracks.count)").font(.title3.bold())
                if tracks.isEmpty {
                    ContentUnavailableView("Ничего не найдено", systemImage: "magnifyingglass", description: Text("Попробуй другое название или имя исполнителя."))
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                            PulseTrackRow(track: track, index: index + 1) { focused = false; store.play(track, within: tracks) }
                            Rectangle().fill(PulseTheme.line).frame(height: 1).padding(.leading, 70)
                        }
                    }
                }
            }.padding(22)
        }
        .refreshable { await store.refresh() }
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        #endif
    }
}

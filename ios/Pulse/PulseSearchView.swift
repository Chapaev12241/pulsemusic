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
    @Environment(\.pulseReducedMotion) private var reducedMotion
    @State private var query = ""
    @FocusState private var focused: Bool
    private var artists: [String] {
        PulseArtistCatalog.names(in: store.tracks).filter { PulseSearch.matches($0, query: query) }
    }
    private var tracks: [PulseTrack] {
        store.tracks.filter { PulseSearch.matches($0.title + " " + $0.artist + " " + ($0.album ?? ""), query: query) }
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Поиск").font(PulseTheme.display(36))
                    Text("Тот самый трек уже где-то здесь.").font(PulseTheme.body(15)).foregroundStyle(PulseTheme.muted)
                }
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass").foregroundStyle(PulseTheme.accent)
                    TextField("Трек, исполнитель, альбом", text: $query).font(PulseTheme.body(16)).textFieldStyle(.plain).focused($focused)
                        #if os(iOS)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.search)
                        #endif
                        .onSubmit { focused = false }
                    if !query.isEmpty {
                        Button { query = ""; focused = true } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(PulseTactileButton()).accessibilityLabel("Очистить поиск")
                    }
                }.padding(18).background(PulseTheme.panel, in: RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(focused ? PulseTheme.accent.opacity(0.55) : PulseTheme.line))
                    .animation(reducedMotion ? nil : .easeOut(duration: 0.18), value: focused)
                if !artists.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(query.isEmpty ? "Исполнители" : "Найденные исполнители").font(PulseTheme.body(24, weight: .bold))
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 12) {
                                ForEach(artists, id: \.self) { name in
                                    PulseArtistCard(store: store, artist: name, size: 140, onOpen: { focused = false })
                                }
                            }.padding(.vertical, 2)
                        }
                    }
                }
                HStack {
                    Text(query.isEmpty ? "Вся музыка" : "Треки").font(PulseTheme.body(24, weight: .bold))
                    Spacer()
                    Text(PulseLibrary.trackCount(tracks.count)).font(PulseTheme.body(12)).foregroundStyle(PulseTheme.muted)
                }
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
            }.padding(22).frame(maxWidth: 1120).frame(maxWidth: .infinity)
        }
        .refreshable { await store.refresh() }
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        #endif
    }
}

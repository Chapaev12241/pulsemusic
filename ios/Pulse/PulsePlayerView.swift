import SwiftUI

struct PulsePlayerBar: View {
    @ObservedObject var store: PulseStore
    @ObservedObject private var playback: PulseTransport
    @State private var expanded = false
    @State private var swipe = PulseSwipeMotion()
    @Environment(\.pulseReducedMotion) private var systemReducedMotion
    @AppStorage("pulse_reduce_motion") private var appReducedMotion = false
    init(store: PulseStore) { self.store = store; playback = store.playback.transport }
    var body: some View {
        Group {
            #if os(macOS)
            desktopPlayer
            #else
            mobilePlayer
            #endif
        }
        .animation(systemReducedMotion || appReducedMotion ? nil : .easeOut(duration: 0.2), value: store.currentID)
        #if os(macOS)
        .background(PulseGlassBackground(radius: 0)).overlay(alignment: .top) { Rectangle().fill(PulseTheme.line).frame(height: 1) }
        #else
        .pulseGlass(cornerRadius: 24, style: .chrome).padding(.horizontal, 12)
        #endif
        .sheet(isPresented: $expanded) { PulseExpandedPlayer(store: store).preferredColorScheme(.dark).tint(PulseTheme.accent) }
    }
    private var desktopPlayer: some View {
        HStack(spacing: 24) {
            nowPlaying.contentShape(Rectangle()).onTapGesture { if store.currentTrack != nil { expanded = true } }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 8) {
                controls(large: false)
                PulseTimeline(store: store)
            }.frame(maxWidth: 400)
            HStack(spacing: 12) {
                PulseDevicesButton(store: store)
                Button { store.dj.toggle() } label: {
                    Text("DJ").font(PulseTheme.body(10, weight: .semibold)).padding(.horizontal, 9).padding(.vertical, 7)
                        .foregroundStyle(store.dj ? PulseTheme.accent : PulseTheme.muted)
                        .background(store.dj ? PulseTheme.accent.opacity(0.12) : PulseTheme.raised, in: RoundedRectangle(cornerRadius: 7))
                }.buttonStyle(PulseTactileButton()).help("Плавные переходы между треками")
                Image(systemName: "speaker.wave.2").font(PulseTheme.body(14)).foregroundStyle(PulseTheme.muted)
                Slider(value: $store.volume, in: 0...1).frame(width: 88).controlSize(.small).accessibilityLabel("Громкость")
                Text("\(Int(store.volume * 100))%").font(PulseTheme.body(10).monospacedDigit()).foregroundStyle(PulseTheme.muted).frame(width: 32)
            }.frame(maxWidth: .infinity, alignment: .trailing)
        }.padding(.horizontal, 28).padding(.vertical, 18).frame(height: 110)
    }
    private var mobilePlayer: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Button { if store.currentTrack != nil && abs(swipe.offset) < 5 { expanded = true } } label: {
                    PulseSwipeDeck(motion: swipe, current: store.currentTrack, incoming: store.adjacentTrack, width: 300, reducedMotion: systemReducedMotion || appReducedMotion) { track in
                        compactTrack(track).padding(.vertical, 2).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.buttonStyle(PulseTactileButton()).clipped()
                Spacer(minLength: 0)
                PulseDevicesButton(store: store)
                PulseShuffleButton(store: store)
                Button { store.togglePlayback() } label: { Image(systemName: playback.paused ? "play.fill" : "pause.fill").font(PulseTheme.body(19)).contentTransition(.symbolEffect(.replace)).animation(systemReducedMotion || appReducedMotion ? nil : .spring(response: 0.28, dampingFraction: 0.78), value: playback.paused).frame(width: 34, height: 40) }.buttonStyle(PulseTactileButton(feedback: .transport)).disabled(store.currentTrack == nil).accessibilityLabel(playback.paused ? "Воспроизвести" : "Пауза")
            }.padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 10)
            PulseMiniProgress(playback: store.playback).padding(.horizontal, 24).padding(.bottom, 2)
        }
        .scaleEffect(expanded && !systemReducedMotion && !appReducedMotion ? 0.985 : 1)
        .animation(systemReducedMotion || appReducedMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86), value: expanded)
        .simultaneousGesture(DragGesture(minimumDistance: 16)
            .onChanged { value in if store.currentTrack != nil { swipe.drag(value) } }
            .onEnded { value in if store.currentTrack != nil { swipe.end(value, width: 300, reducedMotion: systemReducedMotion || appReducedMotion, action: store.next) } })
        .accessibilityAction(named: "Предыдущий трек") { store.next(-1) }
        .accessibilityAction(named: "Следующий трек") { store.next(1) }
    }
    private func compactTrack(_ track: PulseTrack?) -> some View {
        HStack(spacing: 12) {
            PulseArtworkView(track: track, size: 46, radius: 12)
            VStack(alignment: .leading, spacing: 6) {
                Text(track?.title ?? "На твоей волне").font(PulseTheme.body(13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                Text(track?.artist ?? "Выбери свой первый трек").font(PulseTheme.body(11)).foregroundStyle(PulseTheme.muted).lineLimit(1)
            }
        }
    }
    private var nowPlaying: some View {
        HStack(spacing: 12) {
            PulseArtworkView(track: store.currentTrack, size: 52, radius: 14)
            VStack(alignment: .leading, spacing: 6) {
                Text(store.currentTrack?.title ?? "На твоей волне").font(PulseTheme.body(14, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                Text(playback.buffering ? "Загрузка…" : store.currentTrack?.artist ?? "Выбери свой первый трек").font(PulseTheme.body(12)).foregroundStyle(PulseTheme.muted).lineLimit(1)
            }
            #if os(macOS)
            if let track = store.currentTrack {
                PulseHeartButton(store: store, track: track)
            }
            #endif
        }
    }
    private func controls(large: Bool) -> some View {
        HStack(spacing: large ? 34 : 24) {
            PulseShuffleButton(store: store).frame(width: 34)
            Button { store.next(-1) } label: { Image(systemName: "backward.end.fill").font(.system(size: large ? 22 : 15)) }.buttonStyle(PulseTactileButton(feedback: nil)).accessibilityLabel("Предыдущий трек")
            Button { store.togglePlayback() } label: {
                Image(systemName: playback.paused ? "play.fill" : "pause.fill").font(.system(size: large ? 24 : 17)).foregroundStyle(.black)
                    .frame(width: large ? 62 : 38, height: large ? 62 : 38).background(Color.white, in: Circle())
            }.buttonStyle(PulseTactileButton(feedback: .transport)).accessibilityLabel(playback.paused ? "Воспроизвести" : "Пауза")
            Button { store.next(1) } label: { Image(systemName: "forward.end.fill").font(.system(size: large ? 22 : 15)) }.buttonStyle(PulseTactileButton(feedback: nil)).accessibilityLabel("Следующий трек")
            Color.clear.frame(width: 34, height: 40).accessibilityHidden(true)
        }.disabled(store.currentTrack == nil)
    }
}

struct PulseTimeline: View {
    @ObservedObject var store: PulseStore
    @ObservedObject private var playback: PulsePlayback
    @State private var seeking = false
    @State private var seekTime = 0.0
    init(store: PulseStore) { self.store = store; playback = store.playback }
    var body: some View {
        HStack(spacing: 10) {
            Text(Self.clock(seeking ? seekTime : playback.time)).frame(width: 32, alignment: .leading)
            Slider(value: Binding(get: { seeking ? seekTime : min(playback.time, max(playback.duration, 1)) }, set: { seekTime = $0; if seeking { PulseHaptics.scrub(to: $0) } }), in: 0...max(playback.duration, 1)) { editing in
                seeking = editing
                if editing { seekTime = playback.time; PulseHaptics.beginScrub(at: seekTime) } else { store.seek(seekTime); PulseHaptics.endScrub() }
            }.controlSize(.small).disabled(store.currentTrack == nil).accessibilityLabel("Позиция воспроизведения")
            Text(Self.clock(playback.duration)).frame(width: 32, alignment: .trailing)
        }.font(PulseTheme.body(10).monospacedDigit()).foregroundStyle(PulseTheme.muted)
        .onDisappear { PulseHaptics.endScrub(completed: false) }
    }
    private static func clock(_ value: Double) -> String {
        guard value.isFinite, value >= 0 else { return "0:00" }
        return String(format: "%d:%02d", Int(value) / 60, Int(value) % 60)
    }
}

struct PulseExpandedPlayer: View {
    @ObservedObject var store: PulseStore
    @ObservedObject private var playback: PulseTransport
    @Environment(\.dismiss) private var dismiss
    @Environment(\.pulseReducedMotion) private var reducedMotion
    @State private var swipe = PulseSwipeMotion()
    @State private var seekFrame = CGRect.null
    @State private var selectedArtist: PulseArtistSelection?
    init(store: PulseStore) { self.store = store; playback = store.playback.transport }
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 26) {
                    HStack {
                        Button { dismiss() } label: { Image(systemName: "chevron.down").frame(width: 36, height: 36) }.buttonStyle(PulseTactileButton())
                        Spacer()
                        Text("Сейчас играет").font(PulseTheme.body(13, weight: .medium)).foregroundStyle(PulseTheme.muted)
                        Spacer()
                        if let track = store.currentTrack {
                            PulseHeartButton(store: store, track: track)
                        }
                    }
                    Spacer(minLength: 10)
                    PulseSwipeDeck(motion: swipe, current: store.currentTrack, incoming: store.adjacentTrack, width: geometry.size.width, reducedMotion: reducedMotion) { track in
                        VStack(spacing: 30) {
                            PulseArtworkView(track: track, size: min(max(geometry.size.width - 64, 120), 360), radius: 30)
                                .shadow(color: .black.opacity(0.25), radius: 22, y: 14)
                            VStack(alignment: .leading, spacing: 9) {
                                Text(track?.title ?? "Выбери трек").font(PulseTheme.display(28)).lineLimit(2).minimumScaleFactor(0.8)
                                if let track, !PulseSearch.key(track.artist).isEmpty {
                                    Button {
                                        guard !swipe.committing, abs(swipe.offset) < 5, track.id == store.currentTrack?.id else { return }
                                        selectedArtist = PulseArtistSelection(name: track.artist)
                                    } label: {
                                        HStack(spacing: 7) {
                                            Text(track.artist).font(PulseTheme.body(16)).lineLimit(2)
                                            Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).accessibilityHidden(true)
                                        }.foregroundStyle(PulseTheme.muted).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                                    }.buttonStyle(PulseTactileButton(feedback: .navigation))
                                        .disabled(swipe.committing || abs(swipe.offset) >= 5 || track.id != store.currentTrack?.id)
                                        .accessibilityLabel("Открыть исполнителя \(track.artist)")
                                } else {
                                    Text("Твоя музыка в Pulse").font(PulseTheme.body(16)).foregroundStyle(PulseTheme.muted)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.frame(maxWidth: 400)
                    }
                    .simultaneousGesture(DragGesture(minimumDistance: 20)
                        .onChanged { value in if store.currentTrack != nil { swipe.drag(value) } }
                        .onEnded { value in if store.currentTrack != nil { swipe.end(value, width: geometry.size.width, reducedMotion: reducedMotion, action: store.next) } })
                    PulseTimeline(store: store)
                        .background(GeometryReader { proxy in Color.clear.preference(key: PulseSeekFrameKey.self, value: proxy.frame(in: .named("PulseFullPlayer"))) })
                    HStack(spacing: 0) {
                        PulseShuffleButton(store: store).frame(width: 34)
                        Spacer(minLength: 4)
                        Button { swipe.advance(-1, width: geometry.size.width, reducedMotion: reducedMotion, action: store.next) } label: {
                            Image(systemName: "backward.end.fill").font(.title2).frame(width: 44, height: 44)
                        }.buttonStyle(PulseTactileButton(feedback: nil)).accessibilityLabel("Предыдущий трек")
                        Spacer(minLength: 4)
                        Button { store.togglePlayback() } label: {
                            Image(systemName: playback.paused ? "play.fill" : "pause.fill").font(.system(size: 29, weight: .semibold)).foregroundStyle(.black)
                                .contentTransition(.symbolEffect(.replace))
                                .frame(width: 76, height: 76).background(Color.white, in: Circle())
                        }.buttonStyle(PulseTactileButton(feedback: .transport)).accessibilityLabel(playback.paused ? "Воспроизвести" : "Пауза")
                        Spacer(minLength: 4)
                        Button { swipe.advance(1, width: geometry.size.width, reducedMotion: reducedMotion, action: store.next) } label: {
                            Image(systemName: "forward.end.fill").font(.title2).frame(width: 44, height: 44)
                        }.buttonStyle(PulseTactileButton(feedback: nil)).accessibilityLabel("Следующий трек")
                        Spacer(minLength: 4)
                        PulseDevicesButton(store: store).frame(width: 34)
                    }.frame(maxWidth: 400).disabled(store.currentTrack == nil)
                    HStack(spacing: 14) {
                        Toggle("Плавные переходы", isOn: $store.dj).font(PulseTheme.body(13)).tint(PulseTheme.accent)
                        if let track = store.currentTrack {
                            Menu { PulseDownloadAction(track: track, downloads: store.downloads) } label: {
                                Image(systemName: "ellipsis").font(.system(size: 20, weight: .medium)).frame(width: 44, height: 44)
                                    .background(PulseTheme.raised, in: Circle())
                            }
                            #if os(macOS)
                            .menuStyle(.borderlessButton).menuIndicator(.hidden)
                            #endif
                            .fixedSize().accessibilityLabel("Действия с треком")
                        }
                    }.padding(.horizontal, 16).padding(.vertical, 8).background(PulseTheme.panel, in: RoundedRectangle(cornerRadius: 20)).frame(maxWidth: 400)
                    PulseLyricsView(store: store)
                    Spacer(minLength: 20)
                }.padding(.horizontal, 24).padding(.vertical, 20).frame(maxWidth: 448).frame(minHeight: geometry.size.height).frame(maxWidth: .infinity)
            }

        }
        .coordinateSpace(name: "PulseFullPlayer")
        .onPreferenceChange(PulseSeekFrameKey.self) { seekFrame = $0 }
        .animation(reducedMotion ? nil : .spring(response: 0.32, dampingFraction: 0.84), value: playback.paused)
        .background(PulseAmbientBackground())
        .sheet(item: $selectedArtist) { artist in
            PulseArtistPage(store: store, artist: artist.name).environmentObject(store).preferredColorScheme(.dark).tint(PulseTheme.accent)
        }
        #if os(macOS)
        .frame(width: 650, height: 790)
        #endif
    }
}

private struct PulseMiniProgress: View {
    @ObservedObject var playback: PulsePlayback
    @Environment(\.scenePhase) private var phase
    @Environment(\.pulseReducedMotion) private var reducedMotion
    var body: some View {
        Group {
            #if os(iOS)
            PulseSmoothProgress(time: playback.time, duration: playback.duration, trackID: playback.currentID, playing: !playback.paused && !playback.buffering && phase == .active && !reducedMotion)
            #else
            GeometryReader { geometry in
                Rectangle().fill(PulseTheme.accent).frame(width: geometry.size.width * (playback.duration > 0 ? min(1, playback.time / playback.duration) : 0))
            }
            #endif
        }.frame(height: 3).background(PulseTheme.line).clipShape(Capsule())
    }
}

private struct PulseSeekFrameKey: PreferenceKey {
    static let defaultValue = CGRect.null
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

struct PulseShuffleButton: View {
    @ObservedObject var store: PulseStore
    @Environment(\.pulseReducedMotion) private var reducedMotion
    var body: some View {
        Button { store.shuffle.toggle() } label: {
            Image(systemName: "shuffle").font(PulseTheme.body(17, weight: .medium))
                .foregroundStyle(store.shuffle ? PulseTheme.accent : PulseTheme.muted)
                .frame(width: 34, height: 40)
                .scaleEffect(store.shuffle && !reducedMotion ? 1.06 : 1)
                .animation(reducedMotion ? nil : .spring(response: 0.24, dampingFraction: 0.68), value: store.shuffle)
                .overlay(alignment: .bottom) { if store.shuffle { Circle().fill(PulseTheme.accent).frame(width: 4, height: 4).padding(.bottom, 1) } }
        }.buttonStyle(PulseTactileButton(feedback: .shuffle)).accessibilityLabel("Перемешивание").accessibilityValue(store.shuffle ? "Включено" : "Выключено")
    }
}

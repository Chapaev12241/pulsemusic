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
        HStack(spacing: 28) {
            nowPlaying.contentShape(Rectangle()).onTapGesture { if store.currentTrack != nil { expanded = true } }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 8) {
                controls(large: false)
                PulseTimeline(store: store)
            }.frame(maxWidth: 400)
            HStack(spacing: 12) {
                Button { store.dj.toggle() } label: {
                    Text("DJ").font(.system(size: 10, weight: .semibold)).padding(.horizontal, 9).padding(.vertical, 7)
                        .foregroundStyle(store.dj ? PulseTheme.accent : PulseTheme.muted)
                        .background(store.dj ? PulseTheme.accent.opacity(0.12) : PulseTheme.raised, in: RoundedRectangle(cornerRadius: 7))
                }.buttonStyle(.plain).help("Плавные переходы между треками")
                Image(systemName: "speaker.wave.2").font(.system(size: 14)).foregroundStyle(PulseTheme.muted)
                Slider(value: $store.volume, in: 0...1).frame(width: 88).controlSize(.small).accessibilityLabel("Громкость")
                Text("\(Int(store.volume * 100))%").font(.system(size: 10).monospacedDigit()).foregroundStyle(PulseTheme.muted).frame(width: 32)
            }.frame(maxWidth: .infinity, alignment: .trailing)
        }.padding(.horizontal, 24).padding(.vertical, 15).frame(height: 100)
    }
    private var mobilePlayer: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { if store.currentTrack != nil && abs(swipe.offset) < 5 { expanded = true } } label: {
                    PulseSwipeDeck(motion: swipe, current: store.currentTrack, incoming: store.adjacentTrack, width: 300, reducedMotion: systemReducedMotion || appReducedMotion) { track in
                        compactTrack(track).padding(.vertical, 2).frame(maxWidth: .infinity, alignment: .leading).background(PulseTheme.panel.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
                    }
                }.buttonStyle(.plain).clipped()
                Spacer(minLength: 0)
                PulseShuffleButton(store: store)
                Button { store.togglePlayback() } label: { Image(systemName: playback.paused ? "play.fill" : "pause.fill").font(.system(size: 19)).frame(width: 34, height: 40) }.buttonStyle(.plain).disabled(store.currentTrack == nil).accessibilityLabel(playback.paused ? "Воспроизвести" : "Пауза")
                Button { swipe.advance(1, width: 300, reducedMotion: systemReducedMotion || appReducedMotion, action: store.next) } label: { Image(systemName: "forward.end.fill").font(.system(size: 16)).frame(width: 28, height: 40) }.buttonStyle(.plain).disabled(store.currentTrack == nil).accessibilityLabel("Следующий трек")
            }.padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 8)
            PulseMiniProgress(playback: store.playback).padding(.horizontal, 24).padding(.bottom, 2)
        }
        .simultaneousGesture(DragGesture(minimumDistance: 16)
            .onChanged { value in if store.currentTrack != nil { swipe.drag(value) } }
            .onEnded { value in if store.currentTrack != nil { swipe.end(value, width: 300, reducedMotion: systemReducedMotion || appReducedMotion, action: store.next) } })
        .accessibilityAction(named: "Предыдущий трек") { store.next(-1) }
        .accessibilityAction(named: "Следующий трек") { store.next(1) }
    }
    private func compactTrack(_ track: PulseTrack?) -> some View {
        HStack(spacing: 12) {
            PulseArtworkView(track: track, size: 46, radius: 11)
            VStack(alignment: .leading, spacing: 6) {
                Text(track?.title ?? "На твоей волне").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                Text(track?.artist ?? "Выбери свой первый трек").font(.system(size: 10)).foregroundStyle(PulseTheme.muted).lineLimit(1)
            }
        }
    }
    private var nowPlaying: some View {
        HStack(spacing: 12) {
            PulseArtworkView(track: store.currentTrack, size: 46, radius: 11)
            VStack(alignment: .leading, spacing: 6) {
                Text(store.currentTrack?.title ?? "На твоей волне").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                Text(playback.buffering ? "Загрузка…" : store.currentTrack?.artist ?? "Выбери свой первый трек").font(.system(size: 10)).foregroundStyle(PulseTheme.muted).lineLimit(1)
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
            PulseShuffleButton(store: store)
            Button { store.next(-1) } label: { Image(systemName: "backward.end.fill").font(.system(size: large ? 22 : 15)) }.buttonStyle(.plain).accessibilityLabel("Предыдущий трек")
            Button { store.togglePlayback() } label: {
                Image(systemName: playback.paused ? "play.fill" : "pause.fill").font(.system(size: large ? 24 : 17)).foregroundStyle(.black)
                    .frame(width: large ? 62 : 38, height: large ? 62 : 38).background(Color.white, in: Circle())
            }.buttonStyle(.plain).accessibilityLabel(playback.paused ? "Воспроизвести" : "Пауза")
            Button { store.next(1) } label: { Image(systemName: "forward.end.fill").font(.system(size: large ? 22 : 15)) }.buttonStyle(.plain).accessibilityLabel("Следующий трек")
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
            Slider(value: Binding(get: { seeking ? seekTime : min(playback.time, max(playback.duration, 1)) }, set: { seekTime = $0 }), in: 0...max(playback.duration, 1)) { editing in
                seeking = editing
                if editing { seekTime = playback.time } else { store.seek(seekTime) }
            }.controlSize(.small).disabled(store.currentTrack == nil).accessibilityLabel("Позиция воспроизведения")
            Text(Self.clock(playback.duration)).frame(width: 32, alignment: .trailing)
        }.font(.system(size: 10).monospacedDigit()).foregroundStyle(PulseTheme.muted)
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
    init(store: PulseStore) { self.store = store; playback = store.playback.transport }
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 28) {
                    HStack {
                        Button { dismiss() } label: { Image(systemName: "chevron.down").frame(width: 36, height: 36) }.buttonStyle(.plain)
                        Spacer()
                        Text("СЕЙЧАС ИГРАЕТ").font(.system(size: 10, weight: .medium)).tracking(2).foregroundStyle(PulseTheme.muted)
                        Spacer()
                        if let track = store.currentTrack {
                            PulseHeartButton(store: store, track: track)
                        }
                    }
                    Spacer(minLength: 10)
                    PulseSwipeDeck(motion: swipe, current: store.currentTrack, incoming: store.adjacentTrack, width: geometry.size.width, reducedMotion: reducedMotion) { track in
                        VStack(spacing: 28) {
                            PulseArtworkView(track: track, size: min(geometry.size.width - 80, 360), radius: 24)
                            VStack(alignment: .leading, spacing: 10) {
                                Text(track?.title ?? "Выбери трек").font(.system(size: 25, weight: .semibold))
                                Text(track?.artist ?? "Pulse").font(.system(size: 16)).foregroundStyle(PulseTheme.muted)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.padding(16).pulseGlass(cornerRadius: 30)
                    }
                    .simultaneousGesture(DragGesture(minimumDistance: 20)
                        .onChanged { value in if store.currentTrack != nil { swipe.drag(value) } }
                        .onEnded { value in if store.currentTrack != nil { swipe.end(value, width: geometry.size.width, reducedMotion: reducedMotion, action: store.next) } })
                    PulseTimeline(store: store)
                        .background(GeometryReader { proxy in Color.clear.preference(key: PulseSeekFrameKey.self, value: proxy.frame(in: .named("PulseFullPlayer"))) })
                    HStack(spacing: 26) {
                        PulseShuffleButton(store: store)
                        Button { swipe.advance(-1, width: geometry.size.width, reducedMotion: reducedMotion, action: store.next) } label: { Image(systemName: "backward.end.fill").font(.title2) }
                        Button { store.togglePlayback() } label: { Image(systemName: playback.paused ? "play.fill" : "pause.fill").font(.title).foregroundStyle(.black).frame(width: 68, height: 68).background(Color.white, in: Circle()) }
                        Button { swipe.advance(1, width: geometry.size.width, reducedMotion: reducedMotion, action: store.next) } label: { Image(systemName: "forward.end.fill").font(.title2) }
                    }.buttonStyle(.plain).disabled(store.currentTrack == nil)
                    Toggle("DJ · плавные переходы", isOn: $store.dj).font(.system(size: 13)).tint(PulseTheme.accent)
                    PulseLyricsView(store: store)
                    Spacer(minLength: 20)
                }.padding(24).frame(minHeight: geometry.size.height)
            }

        }
        .coordinateSpace(name: "PulseFullPlayer")
        .onPreferenceChange(PulseSeekFrameKey.self) { seekFrame = $0 }
        .background(PulseAmbientBackground())
        #if os(macOS)
        .frame(width: 650, height: 730)
        #endif
    }
}

private struct PulseMiniProgress: View {
    @ObservedObject var playback: PulsePlayback
    var body: some View {
        GeometryReader { geometry in
            Rectangle().fill(PulseTheme.accent).frame(width: geometry.size.width * (playback.duration > 0 ? min(1, playback.time / playback.duration) : 0))
        }.frame(height: 2).background(PulseTheme.line)
    }
}

private struct PulseSeekFrameKey: PreferenceKey {
    static let defaultValue = CGRect.null
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

struct PulseShuffleButton: View {
    @ObservedObject var store: PulseStore
    var body: some View {
        Button { store.shuffle.toggle() } label: {
            Image(systemName: "shuffle").font(.system(size: 17, weight: .medium))
                .foregroundStyle(store.shuffle ? PulseTheme.accent : PulseTheme.muted)
                .frame(width: 34, height: 40)
                .overlay(alignment: .bottom) { if store.shuffle { Circle().fill(PulseTheme.accent).frame(width: 4, height: 4).padding(.bottom, 1) } }
        }.buttonStyle(.plain).accessibilityLabel("Перемешивание").accessibilityValue(store.shuffle ? "Включено" : "Выключено")
    }
}

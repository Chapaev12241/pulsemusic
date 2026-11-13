import SwiftUI
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers
#if os(iOS)
import PhotosUI
import UIKit
#else
import AppKit
#endif

extension Color {
    init(pulseHex: String) {
        let value = UInt64(pulseHex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0xa59aff
        self.init(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
}
struct PulseAvatarView: View {
    let profile: PulseProfile?
    var size: CGFloat = 48
    var body: some View {
        ZStack {
            Circle().fill(Color(pulseHex: profile?.color ?? "#a59aff").gradient)
            if let value = profile?.avatar, let url = URL(string: value), url.scheme == "https", url.host == PulseAPI.base.host {
                AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { symbol }
            } else { symbol }
        }.frame(width: size, height: size).clipShape(Circle()).overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1)).accessibilityHidden(true)
    }
    private var symbol: some View { Text(profile?.emoji ?? "♫").font(.system(size: size * 0.43, weight: .medium)).foregroundStyle(Color.black.opacity(0.75)) }
}
struct PulseAccountBadge: View {
    @ObservedObject var social: PulseSocialStore
    let fallbackName: String?
    let action: () -> Void
    var compact = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                PulseAvatarView(profile: social.profile, size: compact ? 40 : 38)
                if !compact {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(social.profile?.name ?? fallbackName ?? "Войти в Pulse").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                        Text(fallbackName == nil ? "Сохрани свой вайб" : "Профиль и настройки").font(.system(size: 10)).foregroundStyle(PulseTheme.muted)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(PulseTheme.muted)
                }
            }
        }.buttonStyle(PulseTactileButton()).accessibilityLabel("Профиль и настройки")
    }
}
struct PulseProfileView: View {
    @ObservedObject var store: PulseStore
    @ObservedObject private var social: PulseSocialStore
    @State private var editing = false
    @State private var showQR = false
    init(store: PulseStore) { self.store = store; social = store.social }
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 15) {
                    PulseAvatarView(profile: social.profile, size: 104)
                    Text(social.profile?.name ?? store.user?.name ?? "Мой Pulse").font(PulseTheme.heading(34))
                    if let bio = social.profile?.bio, !bio.isEmpty { Text(bio).font(.callout).foregroundStyle(PulseTheme.muted).multilineTextAlignment(.center) }
                    if let email = store.user?.email { Text(email).font(.caption).foregroundStyle(PulseTheme.muted) }
                    Button("Настроить профиль") { editing = true }.buttonStyle(PulsePrimaryButton()).disabled(social.profile == nil)
                }.frame(maxWidth: .infinity).padding(28).pulseGlass(cornerRadius: 24)
                HStack(spacing: 12) {
                    statistic("Музыка", value: store.ownedIDs.count)
                    statistic("Избранное", value: store.state.liked.count)
                    statistic("Друзья", value: social.friends.count)
                }
                if let profile = social.profile {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Твоя музыка объединяет", systemImage: "person.2").font(.headline)
                        Text("Поделись приглашением, чтобы добавить друга и общаться в Pulse.").font(.callout).foregroundStyle(PulseTheme.muted)
                        HStack {
                            ShareLink(item: profile.inviteURL) { Label("Пригласить", systemImage: "square.and.arrow.up") }.buttonStyle(.bordered).tint(PulseTheme.accent)
                            Button { showQR = true } label: { Label("QR-код", systemImage: "qrcode") }.buttonStyle(.bordered).tint(PulseTheme.accent)
                        }
                        Text(profile.id).font(.caption2.monospaced()).foregroundStyle(PulseTheme.muted).textSelection(.enabled)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(22).pulseGlass(cornerRadius: 22)
                }
                if social.loading { ProgressView() }
            }.padding(20)
        }
        .task { await social.refresh() }
        .sheet(isPresented: $editing) { if let profile = social.profile { PulseProfileEditor(profile: profile, social: social) } }
        .sheet(isPresented: $showQR) { if let profile = social.profile { PulseInviteView(profile: profile) } }
        .alert("Профиль", isPresented: Binding(get: { social.error != nil }, set: { if !$0 { social.error = nil } })) { Button("Понятно") { social.error = nil } } message: { Text(social.error ?? "") }
    }
    private func statistic(_ title: String, value: Int) -> some View {
        VStack(spacing: 7) { Text("\(value)").font(.title2.bold()).foregroundStyle(PulseTheme.accent); Text(title).font(.caption).foregroundStyle(PulseTheme.muted) }.frame(maxWidth: .infinity).padding(.vertical, 18).pulseGlass(cornerRadius: 18)
    }
}
struct PulseProfileEditor: View {
    let profile: PulseProfile
    @ObservedObject var social: PulseSocialStore
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var bio: String
    @State private var color: String
    @State private var emoji: String
    @State private var importing = false
    #if os(iOS)
    @State private var photo: PhotosPickerItem?
    #endif
    init(profile: PulseProfile, social: PulseSocialStore) {
        self.profile = profile; self.social = social
        _name = State(initialValue: profile.name); _bio = State(initialValue: profile.bio); _color = State(initialValue: profile.color); _emoji = State(initialValue: profile.emoji)
    }
    private var preview: PulseProfile { var p = profile; p.name = name; p.bio = bio; p.color = color; p.emoji = emoji; p.avatar = social.profile?.avatar ?? profile.avatar; return p }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack { Spacer(); PulseAvatarView(profile: preview, size: 96); Spacer() }.padding(.vertical, 12)
                    #if os(iOS)
                    PhotosPicker(selection: $photo, matching: .images) { Label("Выбрать фотографию", systemImage: "photo") }
                    #else
                    Button { importing = true } label: { Label("Выбрать фотографию", systemImage: "photo") }
                    #endif
                    if social.saving { ProgressView("Сохраняем…") }
                }
                Section("Твой профиль") {
                    TextField("Имя", text: $name)
                    TextField("О себе", text: $bio, axis: .vertical).lineLimit(3...6)
                    Text("\(bio.count) / 300").font(.caption).foregroundStyle(PulseTheme.muted)
                    TextField("Символ аватара", text: $emoji)
                }
                Section("Цвет аватара") {
                    ColorPicker("Свой цвет", selection: Binding(get: { Color(pulseHex: color) }, set: { color = PulseColorValue.hex($0) }), supportsOpacity: false)
                    HStack {
                        ForEach(["#a59aff", "#88baff", "#ff93b7", "#83d7b0", "#e9bd77", "#dc9dea"], id: \.self) { value in
                            Button { color = value } label: { Circle().fill(Color(pulseHex: value)).frame(width: 31, height: 31).overlay(Circle().stroke(color == value ? Color.white : .clear, lineWidth: 3)) }.buttonStyle(PulseTactileButton()).accessibilityLabel("Цвет \(value)")
                        }
                    }
                }
                if let error = social.error { Text(error).foregroundStyle(.red).font(.callout) }
            }
            .formStyle(.grouped).scrollContentBackground(.hidden).background(PulseAmbientBackground())
            .navigationTitle("Твой профиль")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { Task { if await social.updateProfile(name: name.trimmingCharacters(in: .whitespacesAndNewlines), bio: bio, color: color, emoji: emoji) { dismiss() } } }.disabled(social.saving || social.userID != profile.id || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(width: 490, height: 620)
        #endif
        .onChange(of: social.userID) { _, value in if value != profile.id { dismiss() } }
        .onChange(of: name) { _, value in if value.count > 80 { name = String(value.prefix(80)) } }
        .onChange(of: bio) { _, value in if value.count > 300 { bio = String(value.prefix(300)) } }
        .onChange(of: emoji) { _, value in if value.count > 4 { emoji = String(value.prefix(4)) } }
        #if os(iOS)
        .onChange(of: photo) { _, value in Task { guard social.userID == profile.id else { return }; if let data = try? await value?.loadTransferable(type: Data.self) { _ = await social.updateAvatar(data) } } }
        #endif
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image]) { result in
            if case .success(let url) = result { Task {
                guard social.userID == profile.id else { return }
                let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                do { let data = try await Task.detached { try Data(contentsOf: url) }.value; _ = await social.updateAvatar(data) }
                catch { social.error = error.localizedDescription }
            } }
        }
    }
}
struct PulseInviteView: View {
    let profile: PulseProfile
    @Environment(\.dismiss) private var dismiss
    @State private var image: CGImage?
    var body: some View {
        VStack(spacing: 22) {
            HStack { Text("Твой QR-код").font(.title2.bold()); Spacer(); Button("Готово") { dismiss() } }
            PulseAvatarView(profile: profile, size: 72)
            Text(profile.name).font(PulseTheme.heading(32))
            if let image { Image(decorative: image, scale: 1).interpolation(.none).resizable().scaledToFit().frame(width: 230, height: 230).padding(18).background(Color.white, in: RoundedRectangle(cornerRadius: 20)) }
            Text("Друг может отсканировать QR-код или вставить ссылку в разделе «Друзья».").font(.callout).foregroundStyle(PulseTheme.muted).multilineTextAlignment(.center)
            ShareLink(item: profile.inviteURL) { Label("Поделиться приглашением", systemImage: "square.and.arrow.up") }.buttonStyle(PulsePrimaryButton())
        }.padding(28).frame(maxWidth: 420).background(PulseAmbientBackground())
        .task(id: profile.id) {
            let filter = CIFilter.qrCodeGenerator(); filter.message = Data(profile.inviteURL.absoluteString.utf8); filter.correctionLevel = "H"
            if let output = filter.outputImage { image = CIContext().createCGImage(output.transformed(by: CGAffineTransform(scaleX: 8, y: 8)), from: output.extent.applying(CGAffineTransform(scaleX: 8, y: 8))) }
        }
    }
}

struct PulseFriendsView: View {
    @ObservedObject var social: PulseSocialStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var invitation = ""
    @State private var selected: PulseProfile?
    @State private var adding = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Музыка ближе,\nкогда вы вместе.").font(PulseTheme.heading(36))
                VStack(alignment: .leading, spacing: 13) {
                    Text("Добавить друга").font(.headline)
                    TextField("Ссылка приглашения или ID профиля", text: $invitation).textFieldStyle(.roundedBorder)
                    Button { adding = true; Task { if await social.invite(invitation) { invitation = "" }; adding = false } } label: {
                        HStack { if adding { ProgressView().controlSize(.small) }; Text("Отправить заявку") }
                    }.buttonStyle(PulsePrimaryButton()).disabled(adding || invitation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !social.signedIn)
                    if !social.outgoing.isEmpty { Text("Заявок отправлено: \(social.outgoing.count)").font(.caption).foregroundStyle(PulseTheme.muted) }
                }.padding(20).pulseGlass(cornerRadius: 20)
                if !social.incoming.isEmpty {
                    Text("Заявки в друзья").font(.title3.bold())
                    ForEach(social.incoming) { person in
                        VStack(alignment: .leading, spacing: 12) {
                            personRow(person)
                            HStack {
                                Button("Принять") { Task { await social.respond(to: person.id, accept: true) } }.buttonStyle(.borderedProminent).tint(PulseTheme.accent)
                                Button("Отклонить") { Task { await social.respond(to: person.id, accept: false) } }.buttonStyle(.bordered)
                            }
                        }.padding(16).pulseGlass(cornerRadius: 18)
                    }
                }
                HStack { Text("Друзья").font(.title3.bold()); Text("\(social.friends.count)").foregroundStyle(PulseTheme.muted); Spacer(); if social.loading { ProgressView().controlSize(.small) } }
                if social.friends.isEmpty { Text("Пригласи друга по ссылке или QR-коду. После подтверждения заявки здесь появится ваш чат.").foregroundStyle(PulseTheme.muted).font(.callout) }
                ForEach(social.friends) { person in
                    Button { selected = person } label: { HStack { personRow(person); Spacer(); Image(systemName: "bubble.left.and.bubble.right").foregroundStyle(PulseTheme.accent) }.padding(16).pulseGlass(cornerRadius: 18) }.buttonStyle(PulseTactileButton())
                }
                if let error = social.error { Text(error).foregroundStyle(.red).font(.callout) }
            }.padding(20)
        }
        .background(PulseAmbientBackground())
        .sheet(item: $selected) { friend in PulseChatView(friend: friend, social: social) }
        .task {
            while !Task.isCancelled {
                if scenePhase == .active { await social.refresh() }
                do { try await Task.sleep(nanoseconds: 4_000_000_000) } catch { return }
            }
        }
    }
    private func personRow(_ person: PulseProfile) -> some View {
        HStack(spacing: 12) { PulseAvatarView(profile: person); VStack(alignment: .leading, spacing: 5) { Text(person.name).font(.headline); if !person.bio.isEmpty { Text(person.bio).font(.caption).foregroundStyle(PulseTheme.muted).lineLimit(2) } } }
    }
}
struct PulseChatView: View {
    @StateObject private var chat: PulseChatStore
    @ObservedObject private var social: PulseSocialStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.pulseReducedMotion) private var reducedMotion
    @State private var draft = ""
    @State private var follow = true
    init(friend: PulseProfile, social: PulseSocialStore) { _chat = StateObject(wrappedValue: PulseChatStore(friend: friend, social: social)); self.social = social }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) { PulseAvatarView(profile: chat.friend, size: 40); VStack(alignment: .leading, spacing: 3) { Text(chat.friend.name).font(.headline); Text("Личные сообщения").font(.caption).foregroundStyle(PulseTheme.muted) }; Spacer(); Button("Готово") { dismiss() } }.padding(18)
            Divider().overlay(PulseTheme.line)
            if chat.sessionValid { messages; composer }
            else { Text("Войди в аккаунт, чтобы открыть переписку").padding(40); Spacer() }
        }.background(PulseAmbientBackground())
        #if os(macOS)
        .frame(width: 590, height: 660)
        #endif
        .onChange(of: social.userID) { _, _ in if !chat.sessionValid { dismiss() } }
        .task {
            while !Task.isCancelled && chat.sessionValid {
                if scenePhase == .active { await chat.load() }
                do { try await Task.sleep(nanoseconds: 4_000_000_000) } catch { return }
            }
        }
    }
    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if chat.hasMore { Button("Предыдущие сообщения") { Task { await chat.load(older: true) } }.disabled(chat.loading).font(.caption).padding() }
                    if chat.messages.isEmpty { Text(chat.loading ? "Загружаем переписку…" : "Начни разговор — отправь первое сообщение").foregroundStyle(PulseTheme.muted).font(.callout).padding(30) }
                    ForEach(chat.messages) { message in
                        HStack {
                            if message.sender == social.userID { Spacer(minLength: 45) }
                            VStack(alignment: .leading, spacing: 5) {
                                Text(message.body).textSelection(.enabled).font(.system(size: 14))
                                if let date = message.date { Text(date, format: .dateTime.hour().minute()).font(.system(size: 9)).foregroundStyle(PulseTheme.muted) }
                            }.padding(13).background(message.sender == social.userID ? PulseTheme.accent.opacity(0.2) : PulseTheme.raised, in: RoundedRectangle(cornerRadius: 17))
                            if message.sender != social.userID { Spacer(minLength: 45) }
                        }.id(message.id)
                    }
                }.padding(18)
            }
            .simultaneousGesture(DragGesture(minimumDistance: 15).onChanged { _ in follow = false })
            .onChange(of: chat.messages.last?.id) { _, value in if follow, let value { withAnimation(reducedMotion ? nil : .easeOut(duration: 0.2)) { proxy.scrollTo(value, anchor: .bottom) } } }
            .overlay(alignment: .bottomTrailing) { if !follow { Button("К новым сообщениям") { follow = true; if let id = chat.messages.last?.id { proxy.scrollTo(id, anchor: .bottom) } }.font(.caption).buttonStyle(.bordered).padding(12) } }
        }
    }
    private var composer: some View {
        VStack(spacing: 8) {
            if let error = chat.error { Text(error).foregroundStyle(.red).font(.caption) }
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Сообщение", text: $draft, axis: .vertical).lineLimit(1...5).textFieldStyle(.plain).padding(12).background(PulseTheme.raised, in: RoundedRectangle(cornerRadius: 13)).onSubmit(send)
                Button(action: send) { if chat.sending { ProgressView().controlSize(.small).frame(width: 40, height: 40) } else { Image(systemName: "arrow.up").font(.system(size: 17, weight: .semibold)).foregroundStyle(.black).frame(width: 40, height: 40).background(PulseTheme.gradient, in: Circle()) } }.buttonStyle(PulseTactileButton()).disabled(chat.sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.utf16.count > 2000).accessibilityLabel("Отправить сообщение")
            }
            if draft.utf16.count > 1800 { Text("\(draft.utf16.count) / 2000").font(.caption2).foregroundStyle(draft.utf16.count > 2000 ? .red : PulseTheme.muted).frame(maxWidth: .infinity, alignment: .trailing) }
        }.padding(14).background(PulseTheme.panel)
    }
    private func send() { let text = draft; Task { if await chat.send(text) { if draft == text { draft = "" }; follow = true } } }
}

enum PulseColorValue {
    static func hex(_ color: Color) -> String {
        #if os(iOS)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        #else
        let value = NSColor(color).usingColorSpace(.sRGB) ?? .black
        let r = value.redComponent, g = value.greenComponent, b = value.blueComponent
        #endif
        return String(format: "#%02x%02x%02x", Int((min(1, max(0, r)) * 255).rounded()), Int((min(1, max(0, g)) * 255).rounded()), Int((min(1, max(0, b)) * 255).rounded()))
    }
}

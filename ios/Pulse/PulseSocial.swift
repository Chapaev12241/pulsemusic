import SwiftUI
import ImageIO
import UniformTypeIdentifiers

struct PulseProfile: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var bio: String
    var color: String
    var emoji: String
    var avatar: String?
    let role: String?
    var inviteURL: URL {
        var url = URLComponents(url: PulseAPI.base, resolvingAgainstBaseURL: false)!
        url.queryItems = [URLQueryItem(name: "friend", value: id)]
        return url.url!
    }
}
struct PulseCommunity: Decodable {
    let profile: PulseProfile
    let friends: [PulseProfile]
    let incoming: [PulseProfile]
    let outgoing: [String]
}
struct PulseProfileResponse: Decodable { let profile: PulseProfile }
struct PulseAvatarResponse: Decodable { let avatar: String }
struct PulseMessage: Decodable, Identifiable, Equatable {
    let id: Int
    let sender: String
    let recipient: String
    let body: String
    let created_at: String
    var date: Date? { ISO8601DateFormatter.pulse.date(from: created_at) ?? ISO8601DateFormatter().date(from: created_at) }
}
struct PulseMessages: Decodable { let messages: [PulseMessage]; let hasMore: Bool }
struct PulseSent: Decodable { let sent: Bool }
extension ISO8601DateFormatter {
    static let pulse: ISO8601DateFormatter = { let value = ISO8601DateFormatter(); value.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return value }()
}

@MainActor
final class PulseSocialStore: ObservableObject {
    @Published private(set) var profile: PulseProfile?
    @Published private(set) var friends: [PulseProfile] = []
    @Published private(set) var incoming: [PulseProfile] = []
    @Published private(set) var outgoing: [String] = []
    @Published private(set) var loading = false
    @Published private(set) var saving = false
    @Published var error: String?
    private(set) var userID = ""
    private var token = ""
    private var generation = UUID()
    var signedIn: Bool { !token.isEmpty }
    func configure(token: String, userID: String) {
        guard self.token != token || self.userID != userID else { return }
        generation = UUID(); self.token = token; self.userID = userID
        profile = nil; friends = []; incoming = []; outgoing = []; error = nil; loading = false; saving = false
    }
    private func request<T: Decodable>(_ path: String, method: String = "GET", body: Data? = nil, headers: [String: String] = [:], query: [URLQueryItem] = []) async throws -> T {
        guard signedIn else { throw PulseAPIError(status: 401, message: "Войди в аккаунт") }
        let stamp = generation
        let value: T = try await PulseAPI.request(path, token: token, method: method, body: body, headers: headers, query: query)
        guard generation == stamp else { throw CancellationError() }
        return value
    }
    func refresh() async {
        guard signedIn, !loading else { return }
        let stamp = generation
        loading = true
        defer { if generation == stamp { loading = false } }
        do {
            let data: PulseCommunity = try await request("api/community/me")
            if profile != data.profile { profile = data.profile }
            if friends != data.friends { friends = data.friends }
            if incoming != data.incoming { incoming = data.incoming }
            if outgoing != data.outgoing { outgoing = data.outgoing }
        } catch is CancellationError { }
        catch { if generation == stamp { self.error = error.localizedDescription } }
    }
    func updateProfile(name: String, bio: String, color: String, emoji: String) async -> Bool {
        guard !saving else { return false }
        let stamp = generation; saving = true
        defer { if generation == stamp { saving = false } }
        do {
            let data: PulseProfileResponse = try await request("api/community/profile", method: "POST", body: PulseAPI.json(["name": String(name.prefix(80)), "bio": String(bio.prefix(300)), "color": color, "emoji": String(emoji.prefix(4))]))
            profile = data.profile
            return true
        } catch is CancellationError { return false }
        catch { if generation == stamp { self.error = error.localizedDescription }; return false }
    }
    func updateAvatar(_ source: Data) async -> Bool {
        guard !saving else { return false }
        let stamp = generation; saving = true
        defer { if generation == stamp { saving = false } }
        do {
            let jpeg = try await Task.detached(priority: .userInitiated) { try PulseAvatarEncoder.jpeg(source) }.value
            let value: PulseAvatarResponse = try await request("api/community/avatar", method: "POST", body: jpeg, headers: ["Content-Type": "image/jpeg"])
            if var profile { profile.avatar = value.avatar; self.profile = profile }
            return true
        } catch is CancellationError { return false }
        catch { if generation == stamp { self.error = error.localizedDescription }; return false }
    }
    nonisolated static func friendID(from text: String) -> String? {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = URLComponents(string: raw)?.queryItems?.first { $0.name == "friend" }?.value ?? raw
        return UUID(uuidString: candidate)?.uuidString.lowercased()
    }
    func invite(_ text: String) async -> Bool {
        guard let id = Self.friendID(from: text) else { error = "Вставь ссылку приглашения или ID профиля"; return false }
        guard id != userID else { error = "Это твой профиль"; return false }
        do {
            let _: PulseOK = try await request("api/community/request", method: "POST", body: PulseAPI.json(["id": id]))
            await refresh(); return true
        } catch is CancellationError { return false }
        catch { self.error = error.localizedDescription; return false }
    }
    func respond(to id: String, accept: Bool) async {
        do {
            let _: PulseOK = try await request("api/community/respond", method: "POST", body: PulseAPI.json(["id": id, "accept": accept]))
            await refresh()
        } catch is CancellationError { }
        catch { self.error = error.localizedDescription }
    }
    func messages(with friend: String, after: Int = 0, before: Int = 0) async throws -> PulseMessages {
        var query = [URLQueryItem(name: "with", value: friend)]
        if after > 0 { query.append(URLQueryItem(name: "after", value: String(after))) }
        if before > 0 { query.append(URLQueryItem(name: "before", value: String(before))) }
        return try await request("api/community/messages", query: query)
    }
    func send(_ body: String, to friend: String) async throws {
        let _: PulseSent = try await request("api/community/messages", method: "POST", body: PulseAPI.json(["to": friend, "body": body]))
    }
}

enum PulseAvatarEncoder {
    static func jpeg(_ data: Data) throws -> Data {
        guard data.count <= 30 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 512, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else {
            throw PulseAPIError(status: 400, message: "Выбери изображение JPEG, PNG или HEIC до 30 МБ")
        }
        for quality in [0.85, 0.65, 0.45, 0.25] {
            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else { break }
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
            if CGImageDestinationFinalize(destination), output.length <= 256000 { return output as Data }
        }
        throw PulseAPIError(status: 413, message: "Не удалось уменьшить аватарку. Выбери другое изображение.")
    }
}

@MainActor
final class PulseChatStore: ObservableObject {
    @Published private(set) var messages: [PulseMessage] = []
    @Published private(set) var hasMore = false
    @Published private(set) var loading = false
    @Published private(set) var sending = false
    @Published var error: String?
    let friend: PulseProfile
    private let social: PulseSocialStore
    private let owner: String
    init(friend: PulseProfile, social: PulseSocialStore) { self.friend = friend; self.social = social; owner = social.userID }
    var sessionValid: Bool { owner == social.userID && social.signedIn }
    static func merge(_ first: [PulseMessage], _ second: [PulseMessage]) -> [PulseMessage] {
        var result = Dictionary(uniqueKeysWithValues: first.map { ($0.id, $0) })
        for message in second { result[message.id] = message }
        return result.values.sorted { $0.id < $1.id }
    }
    func load(older: Bool = false) async {
        guard sessionValid, !loading else { return }
        loading = true; defer { loading = false }
        do {
            let result = try await social.messages(with: friend.id, after: older ? 0 : messages.last?.id ?? 0, before: older ? messages.first?.id ?? 0 : 0)
            guard sessionValid else { messages = []; return }
            if older || messages.isEmpty { hasMore = result.hasMore }
            messages = Self.merge(messages, result.messages)
        } catch is CancellationError { messages = [] }
        catch { self.error = error.localizedDescription }
    }
    func send(_ text: String) async -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard sessionValid, !sending, !text.isEmpty, text.utf16.count <= 2000 else { return false }
        sending = true; defer { sending = false }
        do { try await social.send(text, to: friend.id); await load(); return true }
        catch is CancellationError { return false }
        catch { self.error = error.localizedDescription; return false }
    }
}

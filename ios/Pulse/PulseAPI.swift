import Foundation
import Security

enum PulseAPI {
    // Uses the existing production accounts, D1 database and R2 music bucket.
    static let base = URL(string: "https://pulse-vibe-music.desyatnichenkoiosyf2.chatgpt.site")!
    static func request<T: Decodable>(_ path: String, token: String = "", method: String = "GET", body: Data? = nil, headers: [String: String] = [:], session: URLSession = .shared) async throws -> T {
        var request = URLRequest(url: base.appendingPathComponent(path), timeoutInterval: 60)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(response.statusCode) else {
            let error = try? JSONDecoder().decode(ErrorBody.self, from: data)
            throw PulseAPIError(status: response.statusCode, message: error?.error ?? "Сервер недоступен (\(response.statusCode))")
        }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw PulseAPIError(status: response.statusCode, message: "Не удалось прочитать ответ сервера. Попробуй обновить медиатеку.") }
    }
    static func json(_ value: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: value) }
    private struct ErrorBody: Decodable { let error: String }
}

enum PulseKeychain {
    private static let service = "com.chapaev12241.pulsemusic.session"
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "pulse_token"]
    }
    static func load() -> String {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func save(_ token: String) throws {
        let data = Data(token.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var q = query
            q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(q as CFDictionary, nil)
            guard added == errSecSuccess else { throw PulseAPIError(status: Int(added), message: "Не удалось сохранить вход в Связке ключей") }
        } else if status != errSecSuccess { throw PulseAPIError(status: Int(status), message: "Не удалось обновить вход в Связке ключей") }
    }
    static func clear() { SecItemDelete(query as CFDictionary) }
}

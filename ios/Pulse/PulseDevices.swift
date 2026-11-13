import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

struct PulseDeviceState: Codable, Equatable, Sendable {
    var trackId: String = ""
    var position: Double = 0
    var duration: Double = 0
    var paused = true
    var buffering = false
    var shuffle = false
    var dj = true
    var volume: Double = 0.8
    var json: [String: Any] { ["trackId": trackId, "position": position.isFinite ? max(0, position) : 0, "duration": duration.isFinite ? max(0, duration) : 0, "paused": paused, "buffering": buffering, "shuffle": shuffle, "dj": dj, "volume": volume] }
}
struct PulseDeviceSnapshot {
    var state: PulseDeviceState
    var queue: [String]
    var originalQueue: [String]
}
struct PulseOnlineDevice: Codable, Identifiable, Equatable, Sendable {
    let id: String, name: String, platform: String
    let online: Bool, ready: Bool
    let lastSeen: Double
    let state: PulseDeviceState
    var symbol: String { platform == "ios" ? "iphone" : platform == "macos" ? "laptopcomputer" : platform == "windows" ? "desktopcomputer" : "globe" }
}
struct PulseDeviceFocus: Codable, Equatable, Sendable {
    var deviceId: String?
    var revision: Int = 0
    var pendingId: String?
    var name: String = ""
    var online = false
    var state: PulseDeviceState?
}
struct PulseDeviceCommand: Decodable, Sendable {
    struct Payload: Decodable, Sendable {
        let state: PulseDeviceState?
        let queue: [String]?
        let originalQueue: [String]?
        let sourceId: String?
        let command: String?
        let position: Double?
        let value: Double?
        let enabled: Bool?
    }
    let id: String, type: String
    let payload: Payload
    let createdAt: Double
}
struct PulseDeviceWatch: Decodable, Sendable { let id: String, status: String, error: String, sourceId: String, targetId: String }
struct PulseDevicesResponse: Decodable, Sendable {
    let deviceId: String
    let devices: [PulseOnlineDevice]
    let focus: PulseDeviceFocus
    let command: PulseDeviceCommand?
    let watched: PulseDeviceWatch?
    let serverTime: Double
}

@MainActor
final class PulseDevices: ObservableObject {
    @Published private(set) var devices: [PulseOnlineDevice] = []
    @Published private(set) var focus = PulseDeviceFocus()
    @Published private(set) var loading = false
    @Published private(set) var transferringTo: String?
    @Published var error: String?
    let id: String
    private(set) var focusReceivedAt = Date()
    private var serverOffset = 0.0
    private var token = "", owner = ""
    private var generation = UUID()
    private var task: Task<Void, Never>?
    private var actionTask: Task<Void, Never>?
    private var syncing = false, claiming = false
    private var pendingID: String?
    private var watch: PulseDeviceWatch?
    private var queueSignature: String?
    private var handled: [String: (Bool, String)] = [:]
    var snapshot: (() -> PulseDeviceSnapshot)?
    var applyCommand: ((PulseDeviceCommand, Double) async throws -> Void)?
    var onFocus: ((PulseDeviceFocus) -> Void)?
    var onActionError: ((String) -> Void)?
    var signedIn: Bool { !token.isEmpty }
    var controlsRemote: Bool { focus.online && focus.deviceId != nil && focus.deviceId != id }
    var onlineDevices: [PulseOnlineDevice] {
        let now = Date().timeIntervalSince1970 * 1000 + serverOffset
        return devices.filter { $0.id == id || ($0.online && now - $0.lastSeen <= 35000) }
    }
    var estimatedRemoteState: PulseDeviceState? {
        guard controlsRemote, var state = focus.state else { return nil }
        if !state.paused && !state.buffering { state.position = min(state.duration > 0 ? state.duration : 86400, state.position + min(6, max(0, Date().timeIntervalSince(focusReceivedAt)))) }
        return state
    }
    private var available: Bool {
        #if os(iOS)
        return UIApplication.shared.applicationState == .active || snapshot?().state.paused == false
        #else
        return true
        #endif
    }
    private var platform: String {
        #if os(iOS)
        return "ios"
        #else
        return "macos"
        #endif
    }
    private var name: String {
        #if os(iOS)
        return UIDevice.current.name
        #else
        return Host.current().localizedName ?? "Mac"
        #endif
    }
    init() {
        if let stored = UserDefaults.standard.string(forKey: "pulse_device_id"), UUID(uuidString: stored) != nil { id = stored.lowercased() }
        else { id = UUID().uuidString.lowercased(); UserDefaults.standard.set(id, forKey: "pulse_device_id") }
    }
    deinit { task?.cancel(); actionTask?.cancel() }
    func configure(token: String, owner: String) {
        guard self.token != token || self.owner != owner else { return }
        let previousToken = self.token
        generation = UUID(); task?.cancel(); actionTask?.cancel(); task = nil; actionTask = nil
        self.token = token; self.owner = owner; devices = []; focus = PulseDeviceFocus(); pendingID = nil; watch = nil; handled = [:]; queueSignature = nil; transferringTo = nil; claiming = false; error = nil
        onFocus?(focus)
        if !previousToken.isEmpty {
            let deviceID = id
            Task { let _: PulseOK? = try? await PulseAPI.request("api/devices", token: previousToken, method: "POST", body: PulseAPI.json(["action": "leave", "deviceId": deviceID])) }
        }
        guard !token.isEmpty else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.available || self.transferringTo != nil { await self.refresh() }
                let active = self.snapshot?().state.paused == false || self.controlsRemote || self.pendingID != nil
                do { try await Task.sleep(nanoseconds: active ? 2_000_000_000 : 6_000_000_000) } catch { return }
            }
        }
    }
    private func post(_ body: [String: Any], token: String) async throws -> PulseDevicesResponse {
        try await PulseAPI.request("api/devices", token: token, method: "POST", body: PulseAPI.json(body))
    }
    private func consume(_ response: PulseDevicesResponse) {
        devices = response.devices; serverOffset = response.serverTime - Date().timeIntervalSince1970 * 1000
        if response.focus.revision >= focus.revision && !(claiming && response.focus.deviceId != id) {
            focus = response.focus; focusReceivedAt = Date(); onFocus?(focus)
        }
        if let watched = response.watched, watched.id == pendingID { watch = watched }
    }
    func refresh() async {
        guard !syncing, !token.isEmpty, let snapshot = snapshot?() else { return }
        syncing = true; loading = devices.isEmpty
        let stamp = generation, session = token
        defer { syncing = false; loading = false }
        do {
            var body: [String: Any] = ["action": "heartbeat", "deviceId": id, "name": name, "platform": platform, "available": available, "ready": available, "state": snapshot.state.json]
            let signature = snapshot.queue.joined(separator: ",") + "|" + snapshot.originalQueue.joined(separator: ",")
            if signature != queueSignature { body["queue"] = Array(snapshot.queue.prefix(2000)); body["originalQueue"] = Array(snapshot.originalQueue.prefix(2000)) }
            if let pendingID { body["watch"] = pendingID }
            let response = try await post(body, token: session)
            guard generation == stamp, !Task.isCancelled else { return }
            queueSignature = signature; consume(response)
            if let command = response.command {
                let result: (Bool, String)
                if let previous = handled[command.id] { result = previous }
                else {
                    do {
                        guard let applyCommand else { throw PulseAPIError(status: 409, message: "Плеер ещё не готов") }
                        try await applyCommand(command, response.serverTime)
                        result = (true, "")
                    } catch { result = (false, error.localizedDescription) }
                    guard generation == stamp else { return }
                    if handled.count > 64 { handled.removeAll() }; handled[command.id] = result
                }
                let ack = try await post(["action": "ack", "deviceId": id, "commandId": command.id, "success": result.0, "error": result.1, "state": self.snapshot?().state.json ?? snapshot.state.json], token: session)
                guard generation == stamp else { return }; consume(ack); queueSignature = nil
            }
            error = nil
        } catch {
            guard generation == stamp, !Task.isCancelled else { return }
            self.error = "Не удалось обновить устройства. Проверь интернет."
        }
    }
    func claimLocal() {
        guard !token.isEmpty else { return }
        claiming = true
        let previous = actionTask, stamp = generation, session = token
        actionTask = Task { [weak self] in
            await previous?.value
            guard let self, self.generation == stamp else { return }
            do {
                await self.refresh()
                let response = try await self.post(["action": "claim", "deviceId": self.id, "state": self.snapshot?().state.json ?? PulseDeviceState().json], token: session)
                guard self.generation == stamp else { return }
                self.claiming = false; self.consume(response); self.queueSignature = nil
            } catch { if self.generation == stamp { self.claiming = false } }
        }
    }
    func control(_ command: String, position: Double? = nil, value: Double? = nil, enabled: Bool? = nil) {
        guard controlsRemote, let target = focus.deviceId else { return }
        let previous = actionTask, stamp = generation, session = token
        var body: [String: Any] = ["action": "control", "deviceId": id, "targetId": target, "requestId": UUID().uuidString.lowercased(), "command": command]
        if let position { body["position"] = position }; if let value { body["value"] = value }; if let enabled { body["enabled"] = enabled }
        actionTask = Task { [weak self] in
            await previous?.value
            guard let self, self.generation == stamp else { return }
            do {
                let response = try await self.post(body, token: session)
                guard self.generation == stamp else { return }; self.consume(response)
            } catch { if self.generation == stamp { self.onActionError?("Не удалось управлять устройством. Обнови список и попробуй ещё раз.") } }
        }
    }
    func transfer(to target: PulseOnlineDevice) async -> Bool {
        guard !token.isEmpty, transferringTo == nil, let snapshot = snapshot?() else { return false }
        error = nil; transferringTo = target.id
        let request = UUID().uuidString.lowercased(), stamp = generation, session = token
        pendingID = request; watch = nil
        defer { if generation == stamp { transferringTo = nil; pendingID = nil; watch = nil } }
        do {
            await refresh()
            let response = try await post(["action": "transfer", "deviceId": id, "targetId": target.id, "requestId": request, "snapshot": snapshot.state.json, "queue": Array(snapshot.queue.prefix(2000)), "originalQueue": Array(snapshot.originalQueue.prefix(2000))], token: session)
            guard generation == stamp else { return false }; consume(response)
            let deadline = Date().addingTimeInterval(28)
            while Date() < deadline && !Task.isCancelled {
                if watch?.status == "applied" { return true }
                if let watched = watch, ["error", "obsolete"].contains(watched.status) { throw PulseAPIError(status: 409, message: watched.error.isEmpty ? "Перенос отменён новым действием" : watched.error) }
                try await Task.sleep(nanoseconds: 600_000_000)
                let response: PulseDevicesResponse = try await PulseAPI.request("api/devices", token: session, query: [URLQueryItem(name: "deviceId", value: id), URLQueryItem(name: "watch", value: request)])
                guard generation == stamp else { return false }; consume(response)
            }
            throw PulseAPIError(status: 408, message: "Устройство не ответило. Музыка осталась на прежнем устройстве.")
        } catch { if generation == stamp { self.error = error.localizedDescription }; return false }
    }
}

struct PulseDevicesButton: View {
    @ObservedObject var store: PulseStore
    @ObservedObject private var devices: PulseDevices
    @State private var showing = false
    init(store: PulseStore) { self.store = store; devices = store.devices }
    var body: some View {
        Button { showing = true } label: {
            Image(systemName: devices.controlsRemote ? "hifispeaker.fill" : "airplay.audio")
                .font(.system(size: 17)).foregroundStyle(devices.controlsRemote ? PulseTheme.accent : PulseTheme.muted).frame(width: 34, height: 40)
        }.buttonStyle(PulseTactileButton(feedback: .navigation)).accessibilityLabel("Устройства в аккаунте")
        .help(devices.controlsRemote ? "Играет на \(devices.focus.name)" : "Передать музыку на другое устройство")
        .sheet(isPresented: $showing) {
            if store.signedIn { PulseDevicesSheet(devices: devices) }
            else { PulseAccountView().environmentObject(store) }
        }
    }
}
private struct PulseDevicesSheet: View {
    @ObservedObject var devices: PulseDevices
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text("Твои устройства").font(.title2.bold()); Spacer(); Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 32, height: 32) }.buttonStyle(PulseTactileButton()) }
            if devices.loading { ProgressView().frame(maxWidth: .infinity) }
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(devices.onlineDevices) { device in
                        let selected = device.id == (devices.focus.deviceId ?? devices.id)
                        Button { Task { if await devices.transfer(to: device) { dismiss() } } } label: {
                            HStack(spacing: 15) {
                                Image(systemName: device.symbol).font(.title2).frame(width: 34)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(device.name).font(.system(size: 15, weight: .semibold))
                                    Text(selected ? "Сейчас играет здесь" : !device.ready ? "Разреши воспроизведение на устройстве" : device.id == devices.id ? "Это устройство" : "Продолжить здесь").font(.caption).foregroundStyle(PulseTheme.muted)
                                }
                                Spacer()
                                if devices.transferringTo == device.id { ProgressView().controlSize(.small) }
                                else if selected { Image(systemName: "checkmark").foregroundStyle(PulseTheme.accent) }
                            }.padding(14).background(selected ? PulseTheme.accent.opacity(0.12) : PulseTheme.panel, in: RoundedRectangle(cornerRadius: 16))
                        }.buttonStyle(PulseTactileButton(feedback: .navigation)).disabled(selected || !device.ready || devices.transferringTo != nil)
                    }
                }
            }
            if let error = devices.error { Text(error).font(.callout).foregroundStyle(.orange) }
            Text("Открой Pulse на другом устройстве и войди в тот же аккаунт.").font(.caption).foregroundStyle(PulseTheme.muted)
        }.padding(24).background(PulseTheme.background).foregroundStyle(.white).preferredColorScheme(.dark).tint(PulseTheme.accent)
        .task { await devices.refresh() }
        #if os(macOS)
        .frame(width: 470, height: 430)
        #else
        .presentationDetents([.medium, .large])
        #endif
    }
}

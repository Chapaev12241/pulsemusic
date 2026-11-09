import Foundation
import CryptoKit
import Combine

// Official Qwen release, pinned to an immutable revision and verified before loading.
enum PulseAIModel {
    #if arch(x86_64)
    static let filename = "Qwen3-0.6B-Q8_0.gguf"
    static let bytes: Int64 = 639_446_688
    static let sha256 = "9465e63a22add5354d9bb4b99e90117043c7124007664907259bd16d043bb031"
    static let url = URL(string: "https://huggingface.co/Qwen/Qwen3-0.6B-GGUF/resolve/23749fefcc72300e3a2ad315e1317431b06b590a/Qwen3-0.6B-Q8_0.gguf?download=true")!
    static let downloadSize = "640 МБ"
    static let modelName = "Qwen3-0.6B · Q8"
    #else
    static let filename = "Qwen3-1.7B-Q4_K_M.gguf"
    static let bytes: Int64 = 1_282_439_264
    static let sha256 = "d2387ca2dbfee2ffabce7120d3770dadca0b293052bc2f0e138fdc940d9bc7b5"
    static let url = URL(string: "https://huggingface.co/ggml-org/Qwen3-1.7B-GGUF/resolve/daeb8e2d528a760970442092f6bf1e55c3b659eb/Qwen3-1.7B-Q4_K_M.gguf?download=true")!
    static let downloadSize = "1,3 ГБ"
    static let modelName = "Qwen3-1.7B · Q4"
    #endif
    static var directory: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Pulse/AI", isDirectory: true) }
    static var file: URL { directory.appendingPathComponent(filename) }
    static var receipt: URL { directory.appendingPathComponent(filename + ".sha256") }
    static var installed: Bool {
        guard let size = try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber,
              size.int64Value == bytes,
              let verified = try? String(contentsOf: receipt, encoding: .utf8) else { return false }
        return verified == sha256
    }
    static func verify(_ file: URL) throws {
        let handle = try FileHandle(forReadingFrom: file); defer { try? handle.close() }
        let size = try handle.seekToEnd(); guard size == UInt64(bytes) else { throw PulseAIError.message("Модель скачалась не полностью. Попробуй ещё раз.") }
        try handle.seek(toOffset: 0)
        var hash = SHA256()
        while let block = try handle.read(upToCount: 4 * 1024 * 1024), !block.isEmpty { try Task.checkCancellation(); hash.update(data: block) }
        guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == sha256 else { throw PulseAIError.message("Проверка модели не прошла. Скачай её повторно.") }
    }
}
enum PulseAIError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
private final class PulseAITransfer: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let progress: @Sendable (Double) -> Void
    private let lock = NSLock()
    private var last = -1.0
    init(progress: @escaping @Sendable (Double) -> Void) { self.progress = progress }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) { }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let value = min(1, Double(totalBytesWritten) / Double(PulseAIModel.bytes))
        lock.lock(); let changed = value - last >= 0.005 || value == 1; if changed { last = value }; lock.unlock()
        if changed { progress(value) }
    }
}
@MainActor
final class PulseAIModelStore: ObservableObject {
    @Published private(set) var ready = PulseAIModel.installed
    @Published private(set) var downloading = false
    @Published private(set) var progress = 0.0
    @Published private(set) var status = ""
    @Published private(set) var error: String?
    private var task: Task<Void, Never>?
    func download() {
        guard !downloading else { return }
        error = nil; downloading = true; progress = 0; status = "Скачиваем модель · \(PulseAIModel.downloadSize)"
        task = Task { [weak self] in
            guard let self else { return }
            defer { self.downloading = false; self.task = nil }
            do {
                var request = URLRequest(url: PulseAIModel.url); request.timeoutInterval = 1800
                let delegate = PulseAITransfer { [weak self] value in Task { @MainActor in self?.progress = value } }
                let (temporary, response) = try await URLSession.shared.download(for: request, delegate: delegate)
                defer { try? FileManager.default.removeItem(at: temporary) }
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw PulseAIError.message("Не удалось скачать модель. Проверь подключение.") }
                try Task.checkCancellation(); self.status = "Проверяем целостность модели…"
                let verification = Task.detached(priority: .utility) { try PulseAIModel.verify(temporary) }
                try await withTaskCancellationHandler(operation: { try await verification.value }, onCancel: { verification.cancel() })
                try Task.checkCancellation()
                try FileManager.default.createDirectory(at: PulseAIModel.directory, withIntermediateDirectories: true)
                try? FileManager.default.removeItem(at: PulseAIModel.file)
                try FileManager.default.moveItem(at: temporary, to: PulseAIModel.file)
                try PulseAIModel.sha256.write(to: PulseAIModel.receipt, atomically: true, encoding: .utf8)
                var excluded = URLResourceValues(); excluded.isExcludedFromBackup = true
                var directory = PulseAIModel.directory; try? directory.setResourceValues(excluded)
                self.ready = true; self.progress = 1; self.status = "Локальный ИИ готов"
            } catch {
                if !Task.isCancelled { self.error = error.localizedDescription }
                self.status = Task.isCancelled ? "Загрузка отменена" : "Не удалось скачать модель"
            }
        }
    }
    func cancel() { task?.cancel() }
    func remove() {
        guard !downloading else { return }
        try? FileManager.default.removeItem(at: PulseAIModel.file); try? FileManager.default.removeItem(at: PulseAIModel.receipt)
        ready = false; progress = 0; status = ""; error = nil
    }
}

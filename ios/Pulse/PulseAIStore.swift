import Foundation
import Combine

@MainActor
final class PulseAIStore: ObservableObject {
    let model = PulseAIModelStore()
    @Published private(set) var building = false
    @Published private(set) var draft: PulseAIDraft?
    @Published private(set) var error: String?
    @Published private(set) var saved = false
    private var owner = "guest"
    private var task: Task<Void, Never>?
    private var generation = UUID()
    func configure(owner: String) {
        guard self.owner != owner else { return }
        cancel(); self.owner = owner; draft = nil; error = nil; saved = false
    }
    func generate(tracks: [PulseTrack], state: PulseLibraryState, prompt: String, mode: PulseVibeMode, seed: String, discovery: Double, playing: Bool) {
        guard !building else { return }
        guard model.ready else { error = "Сначала скачай локальную ИИ-модель."; return }
        guard ProcessInfo.processInfo.thermalState != .critical else { error = "Дай устройству немного остыть перед подбором."; return }
        building = true; error = nil; saved = false
        let stamp = UUID(); generation = stamp
        task = Task(priority: .utility) { [weak self] in
            do {
                let prepared = Task.detached(priority: .utility) { try PulseVibe.prepare(tracks: tracks, state: state, prompt: prompt, mode: mode, seed: seed, discovery: discovery) }
                let input = try await withTaskCancellationHandler(operation: { try await prepared.value }, onCancel: { prepared.cancel() })
                let result = try await PulseLocalAI.shared.generate(input: input, playing: playing)
                guard let self, self.generation == stamp, !Task.isCancelled else { return }
                self.draft = result; self.building = false; self.task = nil
            } catch {
                guard let self, self.generation == stamp else { return }
                if !Task.isCancelled { self.error = error.localizedDescription }
                self.building = false; self.task = nil
            }
        }
    }
    func cancel() { generation = UUID(); task?.cancel(); task = nil; building = false }
    func markSaved() { saved = true }
    func fail(_ message: String) { error = message }
}

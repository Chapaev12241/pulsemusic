import Foundation
import LlamaSwift
import Metal

// The actor runs outside MainActor. Every context is freed after generation;
// playback never shares its queue or performs inference on an audio thread.
actor PulseLocalAI {
    static let shared = PulseLocalAI()
    private static let initialized: Void = { llama_backend_init() }()
    func generate(input: PulseVibeInput, modelURL: URL = PulseAIModel.file, playing: Bool = false, trace: (@Sendable (String) -> Void)? = nil) throws -> PulseAIDraft {
        try Task.checkCancellation()
        _ = Self.initialized
        let virtualGPU = MTLCreateSystemDefaultDevice()?.name.localizedCaseInsensitiveContains("virtual") == true
        var parameters = llama_model_default_params()
        #if arch(x86_64)
        parameters.n_gpu_layers = 0
        #else
        parameters.n_gpu_layers = virtualGPU ? 0 : 16
        #endif
        guard let model = llama_model_load_from_file(modelURL.path, parameters) else { throw PulseAIError.message("Не удалось открыть ИИ-модель. Скачай её повторно.") }
        defer { llama_model_free(model) }
        try Task.checkCancellation()
        guard let vocab = llama_model_get_vocab(model) else { throw PulseAIError.message("Не удалось прочитать словарь модели.") }
        var configuration = llama_context_default_params()
        configuration.n_ctx = 4096; configuration.n_batch = 128; configuration.n_ubatch = 128
        configuration.n_threads = playing ? 2 : Int32(min(4, max(1, ProcessInfo.processInfo.activeProcessorCount / 2)))
        configuration.n_threads_batch = configuration.n_threads
        if virtualGPU { configuration.offload_kqv = false; configuration.op_offload = false }
        #if arch(x86_64)
        configuration.offload_kqv = false; configuration.op_offload = false
        #endif
        guard let context = llama_init_from_model(model, configuration) else { throw PulseAIError.message("Не хватает памяти для ИИ. Закрой тяжёлые приложения и повтори.") }
        defer { llama_free(context) }
        var active = input
        func tokenize(_ text: String) -> [llama_token] {
            let needed = llama_tokenize(vocab, text, Int32(text.utf8.count), nil, 0, true, true)
            var tokens = [llama_token](repeating: 0, count: max(1, Int(abs(needed))))
            let count = llama_tokenize(vocab, text, Int32(text.utf8.count), &tokens, Int32(tokens.count), true, true)
            return count > 0 ? Array(tokens.prefix(Int(count))) : []
        }
        var tokens = tokenize(try PulseVibe.prompt(active))
        while tokens.count > 3500 && active.artists.count > 8 {
            active = PulseVibeInput(artists: Array(active.artists.dropLast(4)), state: active.state, prompt: active.prompt, mode: active.mode, seed: active.seed, discovery: active.discovery, variation: active.variation)
            tokens = tokenize(try PulseVibe.prompt(active))
        }
        trace?("Pulse AI input tokens: \(tokens.count), model: \(modelURL.lastPathComponent)")
        guard !tokens.isEmpty, tokens.count <= 3500 else { throw PulseAIError.message("Запрос слишком длинный. Опиши настроение короче.") }
        guard let sampler = llama_sampler_chain_init(llama_sampler_chain_default_params()),
              let grammar = llama_sampler_init_grammar(vocab, PulseVibe.grammar(artistCount: active.artists.count), "root") else { throw PulseAIError.message("Не удалось подготовить музыкальный ответ ИИ.") }
        defer { llama_sampler_free(sampler) }
        llama_sampler_chain_add(sampler, grammar)
        llama_sampler_chain_add(sampler, llama_sampler_init_top_k(20))
        llama_sampler_chain_add(sampler, llama_sampler_init_top_p(0.9, 1))
        llama_sampler_chain_add(sampler, llama_sampler_init_temp(0.55))
        llama_sampler_chain_add(sampler, llama_sampler_init_dist(UInt32(truncatingIfNeeded: active.variation)))
        let started = Date()
        for start in stride(from: 0, to: tokens.count, by: 128) {
            try Task.checkCancellation()
            let count = min(128, tokens.count - start)
            let result = tokens.withUnsafeMutableBufferPointer { buffer in
                llama_decode(context, llama_batch_get_one(buffer.baseAddress!.advanced(by: start), Int32(count)))
            }
            guard result == 0 else { throw PulseAIError.message("ИИ не смог обработать каталог. Попробуй ещё раз.") }
        }
        var output = Data()
        for _ in 0..<180 {
            try Task.checkCancellation()
            guard Date().timeIntervalSince(started) < 120 else { trace?("Partial model response: " + String(decoding: output, as: UTF8.self)); throw PulseAIError.message("Подбор занял слишком долго. Попробуй более короткий запрос.") }
            let token = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocab, token) { break }
            var piece = [CChar](repeating: 0, count: 256)
            var length = llama_token_to_piece(vocab, token, &piece, Int32(piece.count), 0, false)
            if length < 0 { piece = [CChar](repeating: 0, count: Int(-length)); length = llama_token_to_piece(vocab, token, &piece, Int32(piece.count), 0, false) }
            guard length >= 0 else { throw PulseAIError.message("Не удалось прочитать ответ ИИ.") }
            output.append(contentsOf: piece.prefix(Int(length)).map { UInt8(bitPattern: $0) })
            if let plan = try? JSONDecoder().decode(PulseAIPlan.self, from: output) { return try PulseVibe.draft(plan, input: active) }
            var next = [token]
            let result = next.withUnsafeMutableBufferPointer { llama_decode(context, llama_batch_get_one($0.baseAddress!, 1)) }
            guard result == 0 else { throw PulseAIError.message("ИИ прервал ответ. Попробуй повторить подбор.") }
        }
        throw PulseAIError.message("ИИ не закончил подбор. Уточни настроение и повтори.")
    }
}

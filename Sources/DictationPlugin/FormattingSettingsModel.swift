import Foundation
import LintelSpeech
import Observation

/// What the "Formatting" section of the Dictation pane shows and does: how much to tidy, the servers found on this
/// Mac, the model to use, and a "Try it" button. Nothing here leaves the Mac: every address goes through
/// `LoopbackPolicy`.
@MainActor @Observable
final class FormattingSettingsModel {
    enum TryState: Equatable {
        case idle
        case running
        case result(original: String, text: String, cleaned: Bool)
    }

    /// The values of the popup. A stored `full` is shown, and runs, as Standard while Full is not offered
    /// (`DictationSettings.offersFull`).
    enum TidyChoice: String, CaseIterable, Sendable {
        case off, light, standard, full

        init(_ settings: DictationSettings) {
            switch settings.effectiveLevel {
            case nil: self = .off
            case .light: self = .light
            case .standard: self = .standard
            case .full: self = .full
            }
        }

        /// The level a model runs at, `nil` for Off and Light, which run no model.
        var modelLevel: DictationSettings.CleanupLevel? {
            switch self {
            case .off, .light: nil
            case .standard: .standard
            case .full: .full
            }
        }
    }

    /// The values the popup lists: Full only while it is offered.
    var choices: [TidyChoice] {
        TidyChoice.allCases.filter { $0 != .full || settings.offersFull }
    }

    /// The text "Try it" cleans up.
    static let sample = "yyy no więc jutro mamy spotkanie o dziesiątej nie to znaczy o jedenastej w biurze"

    /// "Tidy up my text": one popup over two keys. Off is `mode = raw` (the stored level stays, so turning it back on
    /// returns to it); Light and Standard are `mode = cleanup` plus `cleanupLevel`.
    var choice: TidyChoice {
        didSet {
            guard choice != oldValue else { return }
            switch choice {
            case .off:
                settings.setMode(.raw)
            case .light:
                settings.setCleanupLevel(.light)
                settings.setMode(.cleanup)
            case .standard:
                settings.setCleanupLevel(.standard)
                settings.setMode(.cleanup)
            case .full:
                settings.setCleanupLevel(.full)
                settings.setMode(.cleanup)
            }
            tryState = .idle
            if usesModel { Task { await refresh() } }
        }
    }
    private(set) var endpoints: [LLMEndpoint] = []
    private(set) var isProbing = false
    private(set) var tryState = TryState.idle
    /// The address field's text; `addressError` is set while it is not a loopback address.
    var address: String {
        didSet { applyAddress() }
    }
    private(set) var addressError = false
    private(set) var selectedEndpoint: URL?
    private(set) var selectedModel: String?

    /// Where the clean-up runs: the user's server or the model Lintel downloaded.
    var source: DictationSettings.LLMSource {
        didSet {
            settings.setLLMSource(source)
            tryState = .idle
            Task { await refresh() }
        }
    }
    /// The built-in models this Mac has the memory for.
    let builtInModels: [LLMModel]
    private(set) var builtInModel: LLMModel
    private(set) var builtInLocation = ModelLocation.missing

    @ObservationIgnored private let settings: DictationSettings
    @ObservationIgnored private let probe: EndpointProbe
    @ObservationIgnored private let transport: any HTTPTransport
    @ObservationIgnored private let llmModels: ModelManager?
    @ObservationIgnored private let runtime: KeepWarmRuntime?
    @ObservationIgnored private var tryTask: Task<Void, Never>?

    /// - Parameters:
    ///   - llmModels: the manager of the built-in models; `nil` hides the built-in source.
    ///   - physicalMemory: decides which catalog models are offered.
    init(
        settings: DictationSettings, transport: any HTTPTransport, llmModels: ModelManager? = nil,
        runtime: KeepWarmRuntime? = nil, physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory
    ) {
        self.settings = settings
        self.llmModels = llmModels
        self.runtime = runtime
        probe = EndpointProbe(transport: transport)
        self.transport = transport
        let offered = LLMModelCatalog.available(physicalMemory: physicalMemory)
        builtInModels = offered.isEmpty ? [LLMModelCatalog.defaultModel] : offered
        let chosen = settings.builtInLLMModel
        builtInModel = builtInModels.contains(chosen) ? chosen : (builtInModels.first ?? chosen)
        source = llmModels == nil ? .server : settings.llmSource
        choice = TidyChoice(settings)
        address = settings.llmEndpoint?.absoluteString ?? ""
        selectedEndpoint = settings.llmEndpoint
        selectedModel = settings.llmModel
    }

    /// Whether anything is tidied (Light, Standard or Full).
    var isCleanupOn: Bool { choice != .off }

    /// Whether a language model (the built-in one or a server) does the tidying: Standard and Full. Light needs none.
    var usesModel: Bool { choice.modelLevel != nil }

    /// Full on the smallest catalog model: it works, but the larger one does it better (spec A6), so the pane says so.
    var showsSmallModelHint: Bool {
        guard choice == .full, isBuiltIn else { return false }
        let smallest = LLMModelCatalog.all.min { $0.residentBytes < $1.residentBytes }
        return builtInModel == smallest
    }

    /// The models of the selected server, from the last probe.
    var models: [String] {
        endpoints.first { $0.baseURL == selectedEndpoint }?.models ?? []
    }

    var offersBuiltIn: Bool { llmModels != nil }
    var isBuiltIn: Bool { source == .builtIn && offersBuiltIn }
    var isBuiltInInstalled: Bool { builtInLocation.folder != nil }

    var hasTarget: Bool {
        isBuiltIn ? isBuiltInInstalled : (selectedEndpoint != nil && selectedModel != nil)
    }

    /// Looks for servers again (the pane calls it when it appears and when the mode is switched on).
    func refresh() async {
        guard usesModel else { return }
        await refreshBuiltIn()
        guard !isBuiltIn else { return }
        isProbing = true
        endpoints = await probe.discover(custom: settings.llmEndpoint)
        isProbing = false
        // Nothing chosen yet: take the first server that has a model.
        if settings.llmTarget == nil, let first = endpoints.first(where: { !$0.models.isEmpty }) {
            chooseEndpoint(first.baseURL)
        } else if let model = selectedModel, !models.isEmpty, !models.contains(model) {
            chooseModel(models.first)
        }
    }

    func refreshBuiltIn() async {
        guard let llmModels else { return }
        builtInLocation = await llmModels.location(of: builtInModel.package)
    }

    func chooseBuiltInModel(_ id: String) {
        guard id != builtInModel.id, let chosen = builtInModels.first(where: { $0.id == id }) else { return }
        builtInModel = chosen
        settings.setBuiltInLLMModel(chosen)
        tryState = .idle
        Task { await refreshBuiltIn() }
    }

    func chooseEndpoint(_ url: URL) {
        guard LoopbackPolicy.isAllowed(url) else { return }
        _ = settings.setLLMEndpoint(url.absoluteString)
        selectedEndpoint = url
        address = url.absoluteString
        chooseModel(endpoints.first { $0.baseURL == url }?.models.first)
    }

    func chooseModel(_ model: String?) {
        settings.setLLMModel(model)
        selectedModel = model
    }

    private func applyAddress() {
        let text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            addressError = false
            return
        }
        if settings.setLLMEndpoint(text) {
            addressError = false
            selectedEndpoint = settings.llmEndpoint
        } else {
            addressError = true
        }
    }

    /// Looks for a server at the typed address.
    func checkAddress() {
        guard !addressError else { return }
        Task { await refresh() }
    }

    /// "Try it": cleans the sample with the chosen model.
    func tryIt() {
        guard tryTask == nil, hasTarget else { return }
        tryState = .running
        let level = choice.modelLevel ?? .standard
        let formatter: any TextFormatter
        if isBuiltIn, let runtime {
            formatter = BuiltInFormatter(runtime: runtime, level: level)
        } else {
            let settings = settings
            formatter = LocalLLMFormatter(transport: transport, target: { settings.llmTarget }, level: level)
        }
        tryTask = Task { [weak self] in
            let sample = Self.sample
            let result = try? await formatter.format(chunk: sample, previousContext: nil)
            guard let self else { return }
            if let result {
                tryState = .result(original: sample, text: result.text, cleaned: result.outcome == .formatted)
            } else {
                tryState = .idle
            }
            tryTask = nil
        }
    }
}

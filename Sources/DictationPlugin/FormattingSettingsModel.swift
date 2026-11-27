import Foundation
import LintelProviders
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

    /// Where the clean-up runs: the user's server, the model Lintel downloaded, or the external AI provider. Choosing the
    /// provider is the consent (no window): it writes `provider` + `providerModel` and the source.
    var source: DictationSettings.LLMSource {
        didSet {
            if source == .provider, settings.providerSelection == nil, let descriptor = Self.descriptor {
                settings.setProvider(
                    DictationSettings.ProviderSelection(provider: descriptor.id, model: descriptor.defaultModelID))
            }
            settings.setLLMSource(source)
            providerModelID = settings.providerSelection?.model ?? providerModelID
            tryState = .idle
            Task { await refresh() }
        }
    }

    /// What the last availability check of the provider found (nothing until it ran).
    enum ProviderCheck: Equatable {
        case unknown
        case checking
        case known(ProviderStatus)
    }

    private(set) var providerCheck = ProviderCheck.unknown
    /// The CLI's version number from the last check.
    private(set) var providerVersion: String?
    /// The descriptor of the provider dictation offers (Claude Code); `nil` when none is known.
    static var descriptor: ProviderDescriptor? { DictationSettings.knownProviders.first }

    /// Reads the provider's model choice again (it is written by `chooseProviderModel`).
    private(set) var providerModelID: String
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
    /// The two content-free probes of the provider (`ProviderRunner.report`); `nil` leaves the provider out of the menu.
    @ObservationIgnored private let providerStatus: (@Sendable (ProviderID) async -> ProviderStatusReport)?
    @ObservationIgnored private var lastProviderProbe: Date?
    @ObservationIgnored private let now: @Sendable () -> Date
    /// A working provider is looked at again after this long (a problem is looked at every time, so a fix shows at once).
    static let providerProbeInterval: TimeInterval = 600
    /// Tells the plugin where the built-in model is, so the formatter's local fallback knows without asking.
    @ObservationIgnored var onBuiltInLocation: (@Sendable (ModelLocation) -> Void)?

    /// - Parameters:
    ///   - llmModels: the manager of the built-in models; `nil` hides the built-in source.
    ///   - physicalMemory: decides which catalog models are offered.
    init(
        settings: DictationSettings, transport: any HTTPTransport, llmModels: ModelManager? = nil,
        runtime: KeepWarmRuntime? = nil, physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory,
        providerStatus: (@Sendable (ProviderID) async -> ProviderStatusReport)? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.settings = settings
        self.llmModels = llmModels
        self.runtime = runtime
        self.providerStatus = providerStatus
        self.now = now
        probe = EndpointProbe(transport: transport)
        self.transport = transport
        let offered = LLMModelCatalog.available(physicalMemory: physicalMemory)
        builtInModels = offered.isEmpty ? [LLMModelCatalog.defaultModel] : offered
        let chosen = settings.builtInLLMModel
        builtInModel = builtInModels.contains(chosen) ? chosen : (builtInModels.first ?? chosen)
        let stored = settings.llmSource
        // A provider that is not chosen (or not offered here) shows as the local source it falls back to.
        if stored == .provider, providerStatus == nil || settings.providerSelection == nil {
            source = llmModels == nil ? .server : .builtIn
        } else {
            source = llmModels == nil && stored != .provider ? .server : stored
        }
        providerModelID =
            settings.providerSelection?.model ?? FormattingSettingsModel.descriptor?.defaultModelID ?? ""
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

    /// Whether the provider is a source here at all (a status probe is wired in).
    var offersProvider: Bool { providerStatus != nil && Self.descriptor != nil }
    var isProvider: Bool { source == .provider && offersProvider }

    /// The status of the provider once a check finished; `nil` while it is unknown or running.
    var providerReadiness: ProviderStatus? {
        if case .known(let status) = providerCheck { return status }
        return nil
    }

    /// D14: the provider is in the menu only while it works (or is already the chosen source, so the row never lies about
    /// the stored choice); "Add a provider…" is always there, for the one that does not.
    var providerIsListed: Bool { offersProvider && (providerReadiness == .ready || isProvider) }

    /// "Try it" needs a target the user's own text can reach on this Mac: not the provider (it is a deliberate send, and
    /// the sample sentence is not worth it).
    var hasTarget: Bool {
        if isProvider { return false }
        return isBuiltIn ? isBuiltInInstalled : (selectedEndpoint != nil && selectedModel != nil)
    }

    /// Whether Claude serves the chosen level; when it does not, the level runs locally and the pane says so.
    var providerServesChosenLevel: Bool {
        guard let level = choice.modelLevel else { return true }
        return ProviderLevels.offered.contains(level)
    }

    /// The local source a level the provider does not serve falls back to, for the line under the source row.
    enum LocalFallback: Equatable {
        case thisMac
        case myServer
        case none
    }

    var localFallback: LocalFallback {
        if isBuiltInInstalled { return .thisMac }
        return settings.llmTarget != nil ? .myServer : .none
    }

    /// Looks for servers again (the pane calls it when it appears and when the mode is switched on).
    func refresh() async {
        guard usesModel else { return }
        await refreshBuiltIn()
        // The provider's state is read while the source row is shown, so Claude is in the menu only when it works
        // (a probe carries no dictated text).
        await refreshProvider()
        guard !isBuiltIn, !isProvider else { return }
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
        onBuiltInLocation?(builtInLocation)
    }

    /// Looks whether the provider's CLI is installed, signed in and of a known version. Runs only while the pane is shown
    /// at a level that uses a model (`refresh()`), never for a plugin that is off, and not again within
    /// `providerProbeInterval` while it works.
    func refreshProvider(force: Bool = false) async {
        guard usesModel, let providerStatus, let descriptor = Self.descriptor else { return }
        if !force, providerReadiness == .ready, let last = lastProviderProbe,
            now().timeIntervalSince(last) < Self.providerProbeInterval
        {
            return
        }
        lastProviderProbe = now()
        #if DEBUG
        if let forced = settings.qaProviderStatus {
            providerCheck = .known(forced)
            providerVersion = forced == .ready ? "2.1.329" : nil
            return
        }
        #endif
        providerCheck = .checking
        let report = await providerStatus(descriptor.id)
        guard !Task.isCancelled else { return }
        providerVersion = report.version
        providerCheck = .known(report.status)
    }

    #if DEBUG
    /// DEBUG only (the design gallery): the state the rows draw, with no process and no model manager.
    func galleryShow(providerCheck check: ProviderCheck, version: String? = nil, builtInInstalled: Bool = false) {
        providerCheck = check
        providerVersion = version
        builtInLocation = builtInInstalled ? .installed(URL(filePath: "/gallery/model")) : .missing
    }
    #endif

    /// "Check Again" of the status line.
    func checkProviderAgain() { Task { await refreshProvider(force: true) } }

    /// The provider's models, as the second menu lists them (the hidden Haiku is not in the descriptor).
    var providerModels: [ProviderModel] { Self.descriptor?.models ?? [] }

    var chosenProviderModel: ProviderModel? { providerModels.first { $0.id == providerModelID } }

    func chooseProviderModel(_ id: String) {
        guard id != providerModelID, providerModels.contains(where: { $0.id == id }),
            let provider = settings.providerSelection?.provider ?? Self.descriptor?.id
        else { return }
        settings.setProvider(DictationSettings.ProviderSelection(provider: provider, model: id))
        providerModelID = id
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

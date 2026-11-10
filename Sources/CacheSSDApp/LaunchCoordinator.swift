import Foundation
import Combine
import CacheSSDCore

enum AppLaunchRequest: Sendable {
    case live, create(URL), resume(URL)
    static func parse(arguments: [String], bundleIdentifier: String?) throws -> AppLaunchRequest {
        let flags = arguments.enumerated().filter { $0.element.hasPrefix("--acceptance-") }
        guard !flags.isEmpty else {
            guard bundleIdentifier != "com.cachessd.app.acceptance" else { throw SampleWorkspace.failure() }
            return .live
        }
        guard bundleIdentifier != "com.cachessd.app", flags.count == 1, let flag = flags.first,
              ["--acceptance-workspace", "--acceptance-session"].contains(flag.element),
              arguments.indices.contains(flag.offset + 1), !arguments[flag.offset + 1].hasPrefix("-") else { throw SampleWorkspace.failure() }
        let path = URL(fileURLWithPath: arguments[flag.offset + 1])
        return flag.element == "--acceptance-session" ? .resume(path) : .create(path)
    }
}

@MainActor final class LaunchCoordinator: ObservableObject {
    @Published private(set) var model: AppModel?
    @Published private(set) var failureMessage: String?
    @Published private(set) var isLoading = true
    private let arguments: [String]
    private let bundleIdentifier: String?
    private let prepare: @Sendable (AppLaunchRequest) throws -> PreparedSampleSession
    private var task: Task<Void, Never>?
    init(arguments: [String] = ProcessInfo.processInfo.arguments, bundleIdentifier: String? = Bundle.main.bundleIdentifier,
         prepare: @escaping @Sendable (AppLaunchRequest) throws -> PreparedSampleSession = { request in
             switch request {
             case .create(let workspace): return try SampleWorkspace.prepare(workspace: workspace)
             case .resume(let session): return try SampleWorkspace.validate(session: session)
             case .live: throw SampleWorkspace.failure()
             }
         }) {
        self.arguments = arguments; self.bundleIdentifier = bundleIdentifier; self.prepare = prepare
    }
    /// Called only after NSApplication has finished launching. In particular,
    /// removable-volume permission cannot block the application's first launch.
    func start() {
        guard model == nil, task == nil else { return }
        failureMessage = nil; isLoading = true
        task = Task {
            do {
                let request = try AppLaunchRequest.parse(arguments: arguments, bundleIdentifier: bundleIdentifier)
                let context: AppContext
                switch request {
                case .live: context = .live()
                case .create, .resume:
                    let prepare = prepare
                    let prepared = try await Task.detached(priority: .userInitiated) { try prepare(request) }.value
                    context = try AppContext.preparedSamples(prepared)
                }
                model = AppModel(context: context)
            } catch {
                // Permission/path details remain private; never substitute live.
                failureMessage = L10n.text("Não foi possível iniciar o modo de amostras. Escolha uma pasta existente, sem links e com espaço disponível.")
            }
            isLoading = false; task = nil
        }
    }
}

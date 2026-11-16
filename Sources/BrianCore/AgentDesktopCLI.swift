import Foundation
import Darwin

/// One bounded subprocess per call. No shell, inherited CLI policy flags, or UI logs.
public struct AgentDesktopCLI: Sendable {
    public let executable: URL
    public let host: URL?
    public let stateRoot: URL
    public init(executable: URL, host: URL? = nil, stateRoot: URL) {
        self.executable = executable; self.host = host; self.stateRoot = stateRoot
    }
    public func call(_ arguments: [String], input: String? = nil) async throws -> JSONValue {
        let worker = CLIWorker()
        return try await withTaskCancellationHandler {
            try await Task.detached { try worker.run(self, arguments: arguments, input: input) }.value
        } onCancel: { worker.cancel() }
    }
    public static func checked(_ envelope: JSONValue) throws -> JSONValue {
        guard envelope["version"].string == "2.6" else { throw AgentError.runtime("Unsupported agent-desktop response version.") }
        guard envelope["ok"].isTrue else {
            let error = envelope["error"]
            throw AgentDesktopFailure(code: error["code"].string ?? "UNKNOWN", delivery: error["disposition"]["delivery"].string,
                                      retry: error["disposition"]["retry"].string)
        }
        return envelope["data"]
    }
}
public struct AgentDesktopFailure: LocalizedError, Sendable {
    public let code: String
    public let delivery: String?
    public let retry: String?
    public var safeToRetry: Bool { delivery == "not_delivered" && retry == "safe" }
    public var errorDescription: String? {
        "agent-desktop: \(code). " + (safeToRetry ? "No input was delivered. No alternate backend was tried." : "The action may have applied. Review the window; Brian will not repeat it through another backend.")
    }
}
private final class CLIWorker: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var grouped = false
    private var cancelled = false
    private var output = Data()
    private var exceeded = false
    func cancel() {
        lock.lock(); cancelled = true
        if let process, process.isRunning { kill(grouped ? -process.processIdentifier : process.processIdentifier, SIGKILL) }
        lock.unlock()
    }
    func run(_ cli: AgentDesktopCLI, arguments: [String], input: String?) throws -> JSONValue {
        guard FileManager.default.isExecutableFile(atPath: cli.executable.path) else { throw AgentError.runtime("The agent-desktop bundle is missing. Use the native backend or rebuild with its pinned bundle.") }
        let child = Process(), stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        child.executableURL = cli.host ?? cli.executable
        child.arguments = (cli.host == nil ? [] : [cli.executable.path]) + arguments
        var environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("AGENT_DESKTOP_") }
        environment["AGENT_DESKTOP_HOME"] = cli.stateRoot.path
        child.environment = environment
        child.currentDirectoryURL = cli.executable.deletingLastPathComponent()
        child.standardInput = stdin; child.standardOutput = stdout; child.standardError = stderr
        lock.lock()
        if cancelled { lock.unlock(); throw CancellationError() }
        process = child; grouped = cli.host != nil
        do { try child.run() } catch { lock.unlock(); throw error }
        lock.unlock()
        let readers = DispatchGroup()
        readers.enter()
        DispatchQueue.global().async { [self] in
            while true {
                let chunk = stdout.fileHandleForReading.availableData
                if chunk.isEmpty { break }
                lock.lock()
                if output.count + chunk.count <= 4_000_000 { output.append(chunk) } else { exceeded = true }
                let over = exceeded; lock.unlock()
                if over { cancel() }
            }
            readers.leave()
        }
        readers.enter()
        DispatchQueue.global().async {
            while !stderr.fileHandleForReading.availableData.isEmpty {}
            readers.leave()
        }
        let timeout = DispatchWorkItem { [self] in cancel() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 25, execute: timeout)
        if let input { try? stdin.fileHandleForWriting.write(contentsOf: Data(input.utf8)) }
        try? stdin.fileHandleForWriting.close()
        child.waitUntilExit(); readers.wait(); timeout.cancel()
        lock.lock(); let data = output, stopped = cancelled, over = exceeded; process = nil; lock.unlock()
        if stopped { throw AgentError.runtime(over ? "agent-desktop exceeded the observation size limit." : "agent-desktop was cancelled or timed out. Input delivery is uncertain; no action was retried.") }
        guard let envelope = try? JSONDecoder().decode(JSONValue.self, from: data) else { throw AgentError.runtime("agent-desktop returned an invalid response. Input delivery is uncertain; no action was retried.") }
        return envelope
    }
}

import Foundation
import Darwin

/// Local MCP transport. All requests stay on stdio; no port or cloud API is used.
public actor MCPRuntime: AgentBackend, LanguagePlanner {
    private let executable: URL
    private let host: URL
    private let timeout: Duration
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var errors: FileHandle?
    private var buffer = Data()
    private var pending: [Int: CheckedContinuation<JSONValue, Error>] = [:]
    private var timers: [Int: Task<Void, Never>] = [:]
    private var nextID = 0
    private var generation = UUID()
    private var initialized = false

    public init(executable: URL, host: URL, timeout: Duration = .seconds(180)) {
        self.executable = executable
        self.host = host
        self.timeout = timeout
    }

    public func status() async throws -> RuntimeStatus {
        try await tool("mac_status").decoded(RuntimeStatus.self)
    }

    public func memory(taskID: String, event: String, context: JSONValue) async throws {
        _ = try await tool("brian_memory", ["task_id": .string(taskID), "event": .string(event), "context": context])
    }

    public func goal(task: String, context: JSONValue) async throws -> TaskGoal {
        try await tool("brian_goal", ["task": .string(task), "context": context]).decoded(TaskGoal.self)
    }
    public func assess(task: String, context: JSONValue) async throws -> CompletionAssessment {
        try await tool("brian_assess", ["task": .string(task), "context": context]).decoded(CompletionAssessment.self)
    }
    public func plan(task: String, context: JSONValue) async throws -> PlannerAction {
        try await tool("brian_plan", ["task": .string(task), "context": context]).decoded(PlannerAction.self)
    }

    public func observe(app: AgentApp) async throws -> Observation {
        try await tool("mac_observe", ["app": .string(app.rawValue)]).decoded(Observation.self)
    }

    public func propose(observation: Observation, task: String, scopeID: String) async throws -> Proposal {
        try await tool("mac_propose", ["snapshot_id": .string(observation.snapshot_id),
                                      "task": .string(task), "scope_id": .string(scopeID)]).decoded(Proposal.self)
    }

    public func execute(proposal: Proposal) async throws {
        let result = try await tool("mac_execute", ["plan_id": .string(proposal.plan_id)])
        guard result["applied"].isTrue else { throw AgentError.runtime("The runtime did not confirm the action. Review the app before retrying.") }
    }

    public func shutdown() async {
        disconnect(CancellationError())
    }

    private func start() async throws {
        if initialized { return }
        guard process == nil else { throw AgentError.runtime("The local model is still starting.") }
        guard FileManager.default.isExecutableFile(atPath: executable.path),
              FileManager.default.isExecutableFile(atPath: host.path) else { throw AgentError.missingRuntime }
        try Task.checkCancellation()
        let child = Process()
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        child.executableURL = host
        child.arguments = [executable.path, "serve"]
        child.currentDirectoryURL = executable.deletingLastPathComponent()
        var environment = ProcessInfo.processInfo.environment
        environment["HF_HUB_OFFLINE"] = "1"
        environment["TRANSFORMERS_OFFLINE"] = "1"
        environment["TOKENIZERS_PARALLELISM"] = "false"
        child.environment = environment
        child.standardInput = stdin
        child.standardOutput = stdout
        child.standardError = stderr
        let current = UUID()
        generation = current
        input = stdin.fileHandleForWriting
        output = stdout.fileHandleForReading
        errors = stderr.fileHandleForReading
        process = child
        // A single reader preserves message ordering, even when reads split a
        // JSON line. availableData only blocks this dedicated background thread.
        let readHandle = stdout.fileHandleForReading
        Thread.detachNewThread { [weak self] in
            while true {
                let data = readHandle.availableData
                if data.isEmpty {
                    Task { await self?.ended(generation: current) }
                    return
                }
                let gate = DispatchSemaphore(value: 0)
                Task {
                    await self?.receive(data, generation: current)
                    gate.signal()
                }
                gate.wait()
            }
        }
        // Always drain stderr to avoid deadlock. Do not persist UI/model data.
        let errorHandle = stderr.fileHandleForReading
        Thread.detachNewThread { while !errorHandle.availableData.isEmpty {} }
        do {
            try child.run()
            try stdin.fileHandleForReading.close()
            try stdout.fileHandleForWriting.close()
            try stderr.fileHandleForWriting.close()
            let response = try await request("initialize", params: .object([
                "protocolVersion": .string("2025-11-25"), "capabilities": .object([:]),
                "clientInfo": .object(["name": .string("brian-computer-use"), "version": .string("0.2.0")]),
            ]))
            guard ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"].contains(response["protocolVersion"].string ?? "") else {
                throw AgentError.runtime("The bundled runtime uses an unsupported MCP protocol version.")
            }
            try write(.object(["jsonrpc": .string("2.0"), "method": .string("notifications/initialized")]))
            initialized = true
        } catch {
            disconnect(error)
            throw error
        }
    }

    private func tool(_ name: String, _ arguments: [String: JSONValue] = [:]) async throws -> JSONValue {
        try await start()
        let result = try await request("tools/call", params: .object(["name": .string(name), "arguments": .object(arguments)]))
        let text = result["content"].array.compactMap { $0["text"].string }.joined(separator: "\n")
        if result["isError"].isTrue { throw AgentError.runtime(text.isEmpty ? "The local model runtime returned an error." : text) }
        if result["structuredContent"] != .null { return result["structuredContent"] }
        guard let data = text.data(using: .utf8), let value = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            throw AgentError.runtime("The local runtime returned an unreadable result.")
        }
        return value
    }

    private func request(_ method: String, params: JSONValue) async throws -> JSONValue {
        try Task.checkCancellation()
        nextID += 1
        let id = nextID
        let current = generation
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                pending[id] = continuation
                timers[id] = Task { [timeout] in
                    do { try await Task.sleep(for: timeout) } catch { return }
                    self.expire(id, generation: current)
                }
                do {
                    try write(.object(["jsonrpc": .string("2.0"), "id": .number(id),
                                       "method": .string(method), "params": params]))
                } catch { disconnect(error) }
            }
        } onCancel: {
            Task { await self.cancel(generation: current) }
        }
    }

    private func write(_ message: JSONValue) throws {
        guard let input else { throw AgentError.runtime("The local model is not running.") }
        var data = try JSONEncoder().encode(message)
        data.append(0x0a)
        try input.write(contentsOf: data)
    }

    private func receive(_ data: Data, generation current: UUID) {
        guard current == generation else { return }
        buffer.append(data)
        guard buffer.count <= 4 * 1024 * 1024 else {
            disconnect(AgentError.runtime("The runtime response exceeded the size limit.")); return
        }
        while let newline = buffer.firstIndex(of: 0x0a) {
            let line = buffer.prefix(upTo: newline)
            buffer.removeSubrange(...newline)
            if line.isEmpty { continue }
            guard let message = try? JSONDecoder().decode(JSONValue.self, from: line) else {
                disconnect(AgentError.runtime("Invalid response from the local model runtime.")); return
            }
            // Handle optional server pings; no other client capabilities were offered.
            if let method = message["method"].string {
                if let id = message["id"].integer {
                    let payload: JSONValue = method == "ping" ? .object([:]) : .object([
                        "code": .number(-32601), "message": .string("Method not supported")])
                    try? write(.object(["jsonrpc": .string("2.0"), "id": .number(id),
                                       method == "ping" ? "result" : "error": payload]))
                }
                continue
            }
            guard let id = message["id"].integer, let continuation = pending.removeValue(forKey: id) else { continue }
            timers.removeValue(forKey: id)?.cancel()
            if message["error"] != .null {
                continuation.resume(throwing: AgentError.runtime(message["error"]["message"].string ?? "Local runtime error."))
            } else {
                continuation.resume(returning: message["result"])
            }
        }
    }

    private func cancel(generation current: UUID) {
        if current == generation { disconnect(CancellationError()) }
    }
    private func expire(_ id: Int, generation current: UUID) {
        if current == generation, pending[id] != nil {
            disconnect(AgentError.runtime("The local model timed out. Review the app before retrying."))
        }
    }
    private func ended(generation current: UUID) {
        if current == generation {
            disconnect(AgentError.runtime("The local model process exited. Retry to restart it."))
        }
    }

    private func disconnect(_ error: Error) {
        generation = UUID()
        initialized = false
        let child = process
        process = nil
        // brian-runtime-host starts an isolated process group, so Stop also
        // reaches an in-flight native helper, not just the Python parent.
        if let child, child.isRunning {
            let pid = child.processIdentifier
            if kill(-pid, SIGTERM) != 0 { child.terminate() }
            Task.detached {
                try? await Task.sleep(for: .milliseconds(500))
                if child.isRunning { _ = kill(-pid, SIGKILL); _ = kill(pid, SIGKILL) }
            }
        }
        try? input?.close()
        // Read handles close on EOF; closing an availableData read from another
        // thread can raise an Objective-C exception.
        input = nil; output = nil; errors = nil
        buffer.removeAll()
        timers.values.forEach { $0.cancel() }
        timers.removeAll()
        let waiting = pending.values
        pending.removeAll()
        waiting.forEach { $0.resume(throwing: error) }
    }
}

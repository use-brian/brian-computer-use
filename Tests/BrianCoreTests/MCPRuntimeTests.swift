import Foundation
import XCTest
@testable import BrianCore

final class MCPRuntimeTests: XCTestCase, @unchecked Sendable {
    func testStdioHandshakeFramingAndRestart() async throws {
        let fixture = try Fixture(mode: "normal")
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let first = try await runtime.status()
        XCTAssertTrue(first.model_available)
        XCTAssertTrue(first.native.accessibility_trusted)
        await runtime.shutdown()
        let second = try await runtime.status()
        XCTAssertTrue(second.adapter_available)
        await runtime.shutdown()
    }

    func testStructuredToolErrorsAreSurfaced() async throws {
        let fixture = try Fixture(mode: "error")
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        do { _ = try await runtime.status(); XCTFail("Expected tool error") }
        catch { XCTAssertEqual(error as? AgentError, .runtime("fixture tool error")) }
        await runtime.shutdown()
    }

    func testTimeoutStopsRuntime() async throws {
        let fixture = try Fixture(mode: "hang")
        defer { fixture.remove() }
        let runtime = fixture.runtime(timeout: .seconds(1))
        do { _ = try await runtime.status(); XCTFail("Expected timeout") }
        catch { XCTAssertTrue(error.localizedDescription.contains("timed out")) }
        await runtime.shutdown()
    }

    func testCancellationInterruptsOutstandingRequest() async throws {
        let fixture = try Fixture(mode: "hang")
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let task = Task { try await runtime.status() }
        try await Task.sleep(for: .milliseconds(250))
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        await runtime.shutdown()
    }

    func testProcessExitDoesNotHang() async throws {
        let fixture = try Fixture(mode: "exit")
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        do { _ = try await runtime.status(); XCTFail("Expected exit error") }
        catch { XCTAssertTrue(error.localizedDescription.contains("exited")) }
        await runtime.shutdown()
    }
}

private struct Fixture {
    let directory: URL
    let host: URL
    init(mode: String) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("brian-mcp-test-\(UUID())")
        host = Bundle(for: MCPRuntimeTests.self).bundleURL.deletingLastPathComponent().appendingPathComponent("brian-runtime-host")
        guard FileManager.default.isExecutableFile(atPath: host.path) else {
            throw AgentError.runtime("Build brian-runtime-host before running transport tests: \(host.path)")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try mode.write(to: directory.appendingPathComponent("mode"), atomically: true, encoding: .utf8)
        let executable = directory.appendingPathComponent("fake-runtime")
        try Self.script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    }
    func runtime(timeout: Duration = .seconds(5)) -> MCPRuntime {
        MCPRuntime(executable: directory.appendingPathComponent("fake-runtime"), host: host, timeout: timeout)
    }
    func remove() { try? FileManager.default.removeItem(at: directory) }
    static let script = #"""
#!/usr/bin/python3
import json, os, sys, time
from pathlib import Path
mode = Path(__file__).with_name('mode').read_text()
assert os.getpgrp() == os.getpid(), 'Runtime must have its own process group'
for line in sys.stdin:
    request = json.loads(line)
    if 'id' not in request:
        continue
    if request['method'] == 'initialize':
        result = {'protocolVersion':'2025-11-25', 'capabilities':{'tools':{}}, 'serverInfo':{'name':'fixture','version':'1'}}
    elif mode == 'hang':
        time.sleep(30)
        continue
    elif mode == 'exit':
        sys.exit(0)
    elif mode == 'error':
        result = {'isError':True,'content':[{'type':'text','text':'fixture tool error'}]}
    else:
        sys.stderr.write('x' * 131072)
        sys.stderr.flush()
        result = {'structuredContent':{'native':{'accessibility_trusted':True},'model_available':True,'adapter_available':True,'model_loaded':True}, 'content':[]}
    data = (json.dumps({'jsonrpc':'2.0','id':request['id'],'result':result}) + '\n').encode()
    for i in range(0, len(data), 7):
        sys.stdout.buffer.write(data[i:i+7])
        sys.stdout.buffer.flush()
"""#
}

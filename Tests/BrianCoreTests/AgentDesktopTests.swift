import XCTest
@testable import BrianCore

final class AgentDesktopTests: XCTestCase {
    private func envelope(_ tree: JSONValue, complete: Bool = true, window: String = "w-1") -> JSONValue {
        .object(["version": .string("2.6"), "ok": .bool(true), "data": .object([
            "window": .object(["id": .string(window), "title": .string("Selected")]),
            "complete": .bool(complete), "tree": tree])])
    }
    func testMappingKeepsQualifiedRefsAndDocumentRowsReadOnly() throws {
        let tree = try JSONDecoder().decode(JSONValue.self, from: Data(#"""
        {"role":"window","children":[
          {"role":"row","ref_id":"@snapshot:e1","available_actions":["Click"],"children":[{"role":"statictext","value":"Example invoice"}]},
          {"role":"webarea","children":[
            {"role":"row","ref_id":"@snapshot:e2","available_actions":["Click"],"name":"Invoice line"},
            {"role":"cell","value":"Invoice total 100","children":[{"role":"statictext","value":"100"}]}
          ]}
        ]}
        """#.utf8))
        let result = try AgentDesktopSnapshot(app: "test", name: "Test", windowID: "w-1", snapshots: [envelope(tree, complete: false)])
        XCTAssertTrue(result.observation.truncated)
        let row = try XCTUnwrap(result.observation.elements.first { $0.label == "Example invoice" })
        XCTAssertTrue(row.selectable)
        XCTAssertEqual(result.targets[row.id]?.ref, "@snapshot:e1")
        XCTAssertFalse(try XCTUnwrap(result.observation.elements.first { $0.label == "Invoice line" }).selectable)
        let value = try XCTUnwrap(result.observation.elements.first { $0.value == "100" })
        XCTAssertNotNil(value.contentGroup)
        let command = try AgentDesktopSnapshot.command(.init(kind: "select", target: row.id), target: result.targets[row.id])
        XCTAssertEqual(command.arguments, ["click", "@snapshot:e1"])
    }
    func testWrongWindowAndUnsupportedEnvelopeAreRejected() throws {
        XCTAssertThrowsError(try AgentDesktopSnapshot(app: "test", name: "Test", windowID: "w-2", snapshots: [envelope(.object([:]))]))
        XCTAssertThrowsError(try AgentDesktopCLI.checked(.object(["version": .string("3.0"), "ok": .bool(true)])))
    }
    func testDeliveryMustBeExplicitlyNotDeliveredAndSafe() {
        for (delivery, retry, safe) in [("not_delivered", "safe", true), ("delivered", "unsafe", false), ("unknown", "safe", false), ("not_delivered", "unknown", false)] {
            let response: JSONValue = .object(["version": .string("2.6"), "ok": .bool(false), "error": .object([
                "code": .string("ACTION_FAILED"), "disposition": .object(["delivery": .string(delivery), "retry": .string(retry)])])])
            XCTAssertThrowsError(try AgentDesktopCLI.checked(response)) { error in
                XCTAssertEqual((error as? AgentDesktopFailure)?.safeToRetry, safe)
            }
        }
    }
    func testTransportDrainsStderrAndPassesTextOnStdin() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: dir) }
        let script = dir.appendingPathComponent("cli")
        try Data("""
        #!/bin/sh
        i=0; while [ "$i" -lt 2000 ]; do echo diagnostic >&2; i=$((i+1)); done
        read value
        if [ "$value" != 'private text' ]; then exit 2; fi
        printf '{"version":"2.6","ok":true,"data":{"accepted":true}}'
        """.utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        let result = try await AgentDesktopCLI(executable: script, stateRoot: dir).call(["set-value", "@s:e1", "--stdin"], input: "private text\n")
        XCTAssertTrue(try AgentDesktopCLI.checked(result)["accepted"].isTrue)
    }
    func testMailSearchHeadingsAreContextNotSelectableResults() throws {
        let tree = try JSONDecoder().decode(JSONValue.self, from: Data(#"""
        {"role":"window","children":[
          {"role":"row","ref_id":"@s:e1","available_actions":["Click"],"name":"Top Results"},
          {"role":"row","ref_id":"@s:e2","available_actions":["Click"],"children":[{"role":"statictext","value":"All Results"}]},
          {"role":"row","ref_id":"@s:e3","available_actions":["Click"],"children":[{"role":"statictext","value":"Invoice for AOGB"}]}
        ]}
        """#.utf8))
        let mapped = try AgentDesktopSnapshot(app: "com.apple.mail", name: "Mail", windowID: "w-1", snapshots: [envelope(tree)])
        for row in mapped.observation.elements.prefix(2) {
            XCTAssertFalse(row.selectable)
            XCTAssertTrue(row.actions.isEmpty)
            XCTAssertThrowsError(try PlannerAction(kind: "select", target: row.id).validate(observation: mapped.observation, apps: []))
        }
        XCTAssertTrue(mapped.observation.elements.last!.selectable)
    }
    func testUncertainActionRequiresExactPostconditionAndCompletePinnedRead() {
        let prior = DesktopElement(id: "ad1", role: "AXRow", label: "Invoice", value: "", enabled: true,
                                   editable: false, actions: ["AXPress"], selectable: true)
        let selected: JSONValue = .object(["role": .string("row"), "states": .array([.string("selected")])])
        let action = PlannerAction(kind: "select", target: "ad1")
        XCTAssertTrue(AgentDesktopSnapshot.verifies(action, prior: prior, rootSnapshot: envelope(selected), windowID: "w-1"))
        XCTAssertFalse(AgentDesktopSnapshot.verifies(action, prior: prior, rootSnapshot: envelope(selected, complete: false), windowID: "w-1"))
        XCTAssertFalse(AgentDesktopSnapshot.verifies(action, prior: prior, rootSnapshot: envelope(selected), windowID: "w-2"))
        XCTAssertFalse(AgentDesktopSnapshot.verifies(action, prior: prior, rootSnapshot: envelope(.object(["role": .string("row")])), windowID: "w-1"))
        XCTAssertFalse(AgentDesktopSnapshot.verifies(.init(kind: "press", target: "ad1"), prior: prior, rootSnapshot: envelope(selected), windowID: "w-1"))
        let field = DesktopElement(id: "ad2", role: "AXTextField", label: "Search", value: "old", enabled: true, editable: true, actions: [])
        let text = PlannerAction(kind: "set_text", target: "ad2", value: "invoice")
        XCTAssertTrue(AgentDesktopSnapshot.verifies(text, prior: field, rootSnapshot: envelope(.object(["value": .string("invoice")])), windowID: "w-1"))
        XCTAssertFalse(AgentDesktopSnapshot.verifies(text, prior: field, rootSnapshot: envelope(.object(["value": .string("invoice partial")])), windowID: "w-1"))
    }
    func testOnlyLivePositiveBoundsMayMovePet() throws {
        let data: JSONValue = .object(["version": .string("2.6"), "ok": .bool(true), "data": .object([
            "live": .bool(true), "property": .string("bounds"),
            "value": .object(["x": .number(-600), "y": .number(100), "width": .decimal(393.5), "height": .number(80)])])])
        XCTAssertEqual(AgentDesktopSnapshot.liveBounds(data), CGRect(x: -600, y: 100, width: 393.5, height: 80))
        XCTAssertNil(AgentDesktopSnapshot.liveBounds(envelope(.object([:]))))
        let stale: JSONValue = .object(["version": .string("2.6"), "ok": .bool(true), "data": .object([
            "live": .bool(false), "property": .string("bounds"), "value": data["data"]["value"]])])
        XCTAssertNil(AgentDesktopSnapshot.liveBounds(stale))
    }
}

import Foundation

public struct AgentDesktopSnapshot: Sendable {
    public struct Target: Sendable {
        public let ref: String?
        public let readRoot: String?
        public let actions: [String]
    }
    public let observation: DesktopObservation
    public let targets: [String: Target]
    public init(app: String, name: String, windowID: String, snapshots: [JSONValue]) throws {
        var rows: [DesktopElement] = [], refs: [String: Target] = [:], seen = Set<String>()
        var truncated = false, characters = 0
        let roles = ["window":"AXWindow", "button":"AXButton", "menubutton":"AXMenuButton", "textfield":"AXTextField", "textarea":"AXTextArea", "combobox":"AXComboBox", "searchfield":"AXSearchField", "scrollarea":"AXScrollArea", "table":"AXTable", "row":"AXRow", "listitem":"AXRow", "treeitem":"AXRow", "cell":"AXCell", "statictext":"AXStaticText", "webarea":"AXWebArea", "document":"AXWebArea", "link":"AXLink", "checkbox":"AXCheckBox", "outline":"AXOutline", "group":"AXGroup"]
        func summary(_ node: JSONValue) -> [String] {
            var parts: [String] = []
            func visit(_ n: JSONValue, _ depth: Int) {
                guard depth < 5, parts.count < 5 else { return }
                let text = n["value"].string ?? n["name"].string ?? ""
                if !text.isEmpty, !parts.contains(text) { parts.append(String(text.prefix(100))) }
                for c in n["children"].array { visit(c, depth + 1) }
            }
            visit(node, 0); return parts
        }
        func walk(_ node: JSONValue, document: Bool = false, parentRef: String? = nil, group: String? = nil) {
            guard rows.count < 180, characters < 26000 else { truncated = true; return }
            let role = roles[node["role"].string ?? ""] ?? "AXGroup"
            let inDocument = document || role == "AXWebArea" || role == "AXTextArea"
            let ref = node["ref_id"].string
            if let ref, !seen.insert(ref).inserted { return }
            let actions = node["available_actions"].array.compactMap(\.string)
            let states = Set(node["states"].array.compactMap(\.string))
            var label = node["name"].string ?? ""
            if role == "AXRow", !inDocument { label = summary(node).joined(separator: " · ") }
            let value = node["value"].string ?? ""
            let id = "ad\(rows.count)"
            let contentGroup = group ?? (inDocument && role == "AXCell" ? id : nil)
            if !label.isEmpty || !value.isEmpty || ref != nil {
                let canClick = ref != nil && actions.contains("Click") && !inDocument && role != "AXLink"
                let row = DesktopElement(id: id, role: role, label: String(label.prefix(180)), value: String(value.prefix(inDocument ? 4000 : 500)),
                    enabled: !states.contains("disabled"), editable: ref != nil && actions.contains("SetValue"),
                    actions: canClick ? ["AXPress"] : [], selectable: canClick && role == "AXRow", selected: states.contains("selected"), contentGroup: contentGroup)
                rows.append(row); characters += row.label.count + row.value.count + 40
                refs[id] = Target(ref: ref, readRoot: ref ?? parentRef, actions: actions)
            }
            if role == "AXRow", !inDocument, !label.isEmpty { return }
            for child in node["children"].array { walk(child, document: inDocument, parentRef: ref ?? parentRef, group: contentGroup) }
        }
        var title = ""
        for snapshot in snapshots {
            let data = try AgentDesktopCLI.checked(snapshot)
            guard data["window"]["id"].string == windowID else { throw AgentError.runtime("agent-desktop returned a different window. Stopped.") }
            title = data["window"]["title"].string ?? title
            truncated = truncated || data["complete"] != .bool(true) || data["truncated"].isTrue
            walk(data["tree"])
        }
        observation = .init(app: app, name: name, window: title, accessibility: true, truncated: truncated, elements: rows)
        targets = refs
    }
    public static func command(_ action: PlannerAction, target: Target?) throws -> (arguments: [String], input: String?) {
        guard let target, let ref = target.ref, ref.first == "@", ref.contains(":e") else { throw AgentError.invalidAction }
        switch action.kind {
        case "press", "select":
            guard target.actions.contains("Click") else { throw AgentError.invalidAction }
            return (["click", ref], nil)
        case "set_text":
            guard target.actions.contains("SetValue") else { throw AgentError.invalidAction }
            return (["set-value", ref, "--stdin"], action.value)
        case "scroll":
            guard target.actions.contains("Scroll"), ["up", "down"].contains(action.value ?? "") else { throw AgentError.invalidAction }
            return (["scroll", ref, "--direction", action.value!, "--amount", "3"], nil)
        default: throw AgentError.invalidAction
        }
    }
}

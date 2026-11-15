import Foundation

/// Keep developer fixtures out of normal app discovery, observation and execution.
public enum DesktopAppPolicy {
    public static func allows(bundleID: String, markedAsTestFixture: Bool = false, allowTestFixtures: Bool = false) -> Bool {
        let fixture = markedAsTestFixture || ["com.usebrian.WorkflowTest", "com.usebrian.NavigationDemo"].contains(bundleID)
        return !fixture || allowTestFixtures
    }
}

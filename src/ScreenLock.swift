// SPDX-License-Identifier: MIT
import AppKit
import ApplicationServices

// Request the real Apple-menu Lock Screen action. This is not proof of lock state.
enum ScreenLockResult { case accepted, unavailable, rejected(Int32) }

final class ScreenLocker {
    private func value(_ element: AXUIElement, _ attribute: String, before deadline: TimeInterval) -> CFTypeRef? {
        guard ProcessInfo.processInfo.systemUptime < deadline else { return nil }
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }
        return result
    }

    private func element(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func target(before deadline: TimeInterval) -> AXUIElement? {
        _ = AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.15)
        // Use the system Finder's Apple menu, not a menu supplied by the frontmost app.
        let finders = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder")
            .filter { $0.bundleURL?.path == "/System/Library/CoreServices/Finder.app" }
        guard finders.count == 1 else { return nil }
        for pid in [finders[0].processIdentifier] {
            let app = AXUIElementCreateApplication(pid)
            guard let bar = element(value(app, kAXMenuBarAttribute, before: deadline)),
                  let barChildren = value(bar, kAXChildrenAttribute, before: deadline) as? [AXUIElement],
                  let appleMenu = barChildren.first,
                  let children = value(appleMenu, kAXChildrenAttribute, before: deadline) as? [AXUIElement],
                  children.count == 1,
                  let menu = children.first,
                  value(menu, kAXRoleAttribute, before: deadline) as? String == kAXMenuRole,
                  let items = value(menu, kAXChildrenAttribute, before: deadline) as? [AXUIElement],
                  items.count <= 32 else { continue }
            var matches: [AXUIElement] = []
            for item in items {
                guard let character = value(item, kAXMenuItemCmdCharAttribute, before: deadline) as? String,
                      character.lowercased() == "q",
                      value(item, kAXTitleAttribute, before: deadline) as? String == "Lock Screen",
                      (value(item, kAXMenuItemCmdModifiersAttribute, before: deadline) as? NSNumber)?.uint32Value == 4,
                      value(item, kAXRoleAttribute, before: deadline) as? String == kAXMenuItemRole,
                      (value(item, kAXEnabledAttribute, before: deadline) as? NSNumber)?.boolValue == true else { continue }
                var actions: CFArray?
                guard ProcessInfo.processInfo.systemUptime < deadline,
                      AXUIElementCopyActionNames(item, &actions) == .success,
                      (actions as? [String])?.contains(kAXPressAction) == true else { continue }
                matches.append(item)
            }
            if matches.count == 1 { return matches[0] }
            if matches.count > 1 { return nil }
        }
        return nil
    }

    func available() -> Bool {
        target(before: ProcessInfo.processInfo.systemUptime + 4) != nil
    }

    func request() -> ScreenLockResult {
        let deadline = ProcessInfo.processInfo.systemUptime + 4
        guard let item = target(before: deadline), ProcessInfo.processInfo.systemUptime < deadline else { return .unavailable }
        let result = AXUIElementPerformAction(item, kAXPressAction as CFString)
        return result == .success ? .accepted : .rejected(result.rawValue)
    }
}

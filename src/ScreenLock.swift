// SPDX-License-Identifier: MIT
import AppKit
import ApplicationServices

// Request the real Apple-menu Lock Screen action. This is not proof of lock state.
enum ScreenLockResult: Equatable { case accepted, unavailable, unconfirmed(Int32), rejected(Int32) }

// Retry only discovery, never a press whose effect may already have occurred.
// Injected operations let the budget and single-press rule be tested without AX.
enum ScreenLockRequest {
    static func run<T>(lookup: (TimeInterval) -> T?, press: (T) -> ScreenLockResult,
                       now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                       pause: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }) -> ScreenLockResult {
        let deadline = now() + 8
        while now() < deadline {
            if let item = lookup(deadline) {
                guard now() < deadline else { return .unavailable }
                return press(item)
            }
            let remaining = deadline - now()
            if remaining > 0 { pause(min(0.1, remaining)) }
        }
        return .unavailable
    }

    static func result(for error: AXError) -> ScreenLockResult {
        if error == .success { return .accepted }
        // Apple documents that cannotComplete may mean a delayed response,
        // including an action that took effect despite the timeout.
        if error == .cannotComplete { return .unconfirmed(error.rawValue) }
        return .rejected(error.rawValue)
    }
}

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
        guard AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 1) == .success else { return nil }
        // Use the system Finder's Apple menu, not a menu supplied by the frontmost app.
        let finders = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder")
            .filter { $0.bundleURL?.path == "/System/Library/CoreServices/Finder.app" }
        guard finders.count == 1 else { return nil }
        let app = AXUIElementCreateApplication(finders[0].processIdentifier)
        guard let bar = element(value(app, kAXMenuBarAttribute, before: deadline)),
              let barChildren = value(bar, kAXChildrenAttribute, before: deadline) as? [AXUIElement],
              let appleMenu = barChildren.first,
              let children = value(appleMenu, kAXChildrenAttribute, before: deadline) as? [AXUIElement],
              children.count == 1,
              let menu = children.first,
              value(menu, kAXRoleAttribute, before: deadline) as? String == kAXMenuRole,
              let items = value(menu, kAXChildrenAttribute, before: deadline) as? [AXUIElement],
              items.count <= 32 else { return nil }
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
        guard matches.count == 1, ProcessInfo.processInfo.systemUptime < deadline else { return nil }
        return matches[0]
    }

    func available() -> Bool {
        target(before: ProcessInfo.processInfo.systemUptime + 4) != nil
    }

    func request() -> ScreenLockResult {
        ScreenLockRequest.run(lookup: { self.target(before: $0) }, press: {
            ScreenLockRequest.result(for: AXUIElementPerformAction($0, kAXPressAction as CFString))
        })
    }
}

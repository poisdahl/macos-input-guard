// SPDX-License-Identifier: MIT
import AppKit

private final class PrivacyPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// An on-screen visual barrier, not a screenshot/capture security boundary.
// No screen capture is performed and no code is entered into these windows.
final class PrivacyOverlay {
    private var panels: [NSPanel] = []
    private var observer: NSObjectProtocol?
    private let instruction: String
    private let coverageLost: () -> Void

    init(instruction: String, coverageLost: @escaping () -> Void) {
        self.instruction = instruction
        self.coverageLost = coverageLost
    }

    @discardableResult
    func show() -> Bool {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        guard rebuild() else { return false }
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            if !self.rebuild() { self.coverageLost() }
        }
        return true
    }

    private func rebuild() -> Bool {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return false }
        var replacement: [NSPanel] = []
        for screen in screens {
            guard screen.frame.width > 0, screen.frame.height > 0 else {
                replacement.forEach { $0.close() }
                return false
            }
            let panel = PrivacyPanel(contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.ignoresMouseEvents = true
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            if #available(macOS 13.0, *) { panel.collectionBehavior.insert(.canJoinAllApplications) }
            let content = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
            let effect = NSVisualEffectView(frame: content.bounds)
            effect.autoresizingMask = [.width, .height]
            effect.blendingMode = .behindWindow
            effect.material = .menu
            effect.state = .active
            effect.alphaValue = 1
            content.addSubview(effect)
            let messagePanel = NSView()
            messagePanel.wantsLayer = true
            messagePanel.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor
            messagePanel.layer?.cornerRadius = 12
            messagePanel.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(messagePanel)
            let label = NSTextField(wrappingLabelWithString: instruction)
            label.font = .systemFont(ofSize: 22, weight: .medium)
            label.textColor = .white
            label.alignment = .center
            label.isSelectable = false
            label.translatesAutoresizingMaskIntoConstraints = false
            messagePanel.addSubview(label)
            NSLayoutConstraint.activate([
                messagePanel.centerXAnchor.constraint(equalTo: content.centerXAnchor),
                messagePanel.centerYAnchor.constraint(equalTo: content.centerYAnchor),
                messagePanel.widthAnchor.constraint(lessThanOrEqualTo: content.widthAnchor, multiplier: 0.9),
                label.leadingAnchor.constraint(equalTo: messagePanel.leadingAnchor, constant: 24),
                label.trailingAnchor.constraint(equalTo: messagePanel.trailingAnchor, constant: -24),
                label.topAnchor.constraint(equalTo: messagePanel.topAnchor, constant: 18),
                label.bottomAnchor.constraint(equalTo: messagePanel.bottomAnchor, constant: -18)
            ])
            panel.contentView = content
            panel.orderFrontRegardless()
            replacement.append(panel)
        }
        // Order replacements first to reduce gaps on display reconfiguration.
        panels.forEach { $0.close() }
        panels = replacement
        return panels.allSatisfy { $0.isVisible }
    }

    func hide() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        panels.forEach { $0.close() }
        panels.removeAll()
    }
}

func stopGuardLoop() {
    if NSApp != nil, NSApp.isRunning {
        NSApp.stop(nil)
        // stop() from a timer needs an app-local event to wake AppKit's run loop.
        // This is not a synthesized keyboard/mouse event.
        if let wake = NSEvent.otherEvent(with: .applicationDefined, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            subtype: 0, data1: 0, data2: 0) {
            NSApp.postEvent(wake, atStart: true)
        }
    }
    CFRunLoopStop(CFRunLoopGetMain())
}

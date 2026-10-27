// SPDX-License-Identifier: MIT
import AppKit
import CoreGraphics

// Construct fixtures only: no event tap, event posting, settings or hardware access.
func fixture(key: UInt32 = 2, state: UInt32 = 0x0a, repeatFlag: UInt32 = 0,
             flags: NSEvent.ModifierFlags = [], subtype: Int16 = 8, pid: Int64 = 0) -> CGEvent {
    let event = NSEvent.otherEvent(with: .systemDefined, location: .zero,
        modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
        subtype: subtype, data1: Int((key << 16) | (state << 8) | repeatFlag), data2: -1)!.cgEvent!
    event.setIntegerValueField(.eventSourceUnixProcessID, value: pid)
    return event
}
func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}

// Isolated down-event predicate tests, followed by stateful sequences below.
func permittedBrightnessControl(_ event: CGEvent) -> BrightnessControl? {
    var policy = BrightnessPassthrough()
    return policy.decision(for: event)?.control
}

let expected: [UInt32: BrightnessControl] = [2: .displayUp, 3: .displayDown, 21: .keyboardUp, 22: .keyboardDown]
for key in UInt32(0)...UInt32(255) {
    require(permittedBrightnessControl(fixture(key: key)) == expected[key], "key allowlist \(key)")
    require(permittedBrightnessControl(fixture(key: key, state: 0x0b)) == nil, "orphan up \(key)")
}
for key in expected.keys {
    require(permittedBrightnessControl(fixture(key: key, repeatFlag: 1)) == nil, "orphan repeat")
    require(permittedBrightnessControl(fixture(key: key, flags: .function)) == expected[key], "Fn brightness")
    for flag: NSEvent.ModifierFlags in [.shift, .control, .option, .command, .capsLock, .numericPad, .help] {
        for state: UInt32 in [0x0a, 0x0b] {
            require(permittedBrightnessControl(fixture(key: key, state: state, flags: flag)) == nil, "modifier shortcut")
        }
        require(permittedBrightnessControl(fixture(key: key, flags: [flag, .function])) == nil, "Fn plus modifier")
    }
    for subtype: Int16 in [0, 1, 7, 10, 11, 12, 13, 16, 17, 100] {
        require(permittedBrightnessControl(fixture(key: key, subtype: subtype)) == nil, "other system subtype")
    }
    for state: UInt32 in [0, 1, 9, 12, 255] {
        require(permittedBrightnessControl(fixture(key: key, state: state)) == nil, "malformed key state")
    }
    require(permittedBrightnessControl(fixture(key: key, repeatFlag: 2)) == nil, "unknown repeat bits")
    require(permittedBrightnessControl(fixture(key: key, state: 0x0b, repeatFlag: 1)) == nil, "repeat on release")
    require(permittedBrightnessControl(fixture(key: key, pid: 123)) == nil, "nonzero source")
    require(permittedBrightnessControl(fixture(key: key, pid: -1)) == nil, "invalid source")
    for bit: UInt in [1, 2, 4, 8, 16, 32, 64, 128, 0x2000] {
        require(permittedBrightnessControl(fixture(key: key, flags: .init(rawValue: bit))) == nil, "device-specific modifier")
    }

    var policy = BrightnessPassthrough()
    require(policy.decision(for: fixture(key: key))?.control == expected[key], "initial down")
    require(policy.decision(for: fixture(key: key, repeatFlag: 1))?.control == expected[key], "paired repeat")
    require(policy.decision(for: fixture(key: key, repeatFlag: 1, flags: .option)) == nil, "modified repeat blocked")
    let release = fixture(key: key, state: 0x0b, flags: [.option, .function])
    let result = policy.decision(for: release)
    require(result?.control == expected[key] && result?.release == true, "release remains paired after modifier change")
    release.flags = CGEventFlags(rawValue: release.flags.rawValue & ~brightnessForbiddenFlags)
    require(release.flags.rawValue & brightnessForbiddenFlags == 0, "paired release strips shortcut modifiers")
    require(release.flags.contains(.maskSecondaryFn), "paired release keeps Fn")
    require(policy.decision(for: fixture(key: key, state: 0x0b)) == nil, "duplicate release blocked")
    require(policy.decision(for: fixture(key: key, repeatFlag: 1)) == nil, "repeat after release blocked")

    var blockedStart = BrightnessPassthrough()
    require(blockedStart.decision(for: fixture(key: key, flags: .option)) == nil, "modified initial down blocked")
    require(blockedStart.decision(for: fixture(key: key, repeatFlag: 1)) == nil, "dropping modifier does not admit an orphan repeat")
    require(blockedStart.decision(for: fixture(key: key, state: 0x0b)) == nil, "blocked press has no forwarded release")

    var retainedModifier = BrightnessPassthrough()
    require(retainedModifier.decision(for: fixture(key: key), currentFlags: { .maskAlternate }) == nil,
            "retained session/hardware modifier blocks otherwise unmodified event")
    require(retainedModifier.decision(for: fixture(key: key, repeatFlag: 1)) == nil, "retained-modifier press never started")
    require(retainedModifier.decision(for: fixture(key: key), currentFlags: { .maskSecondaryFn })?.control == expected[key],
            "Fn in current state remains allowed")
}
for type: CGEventType in [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .scrollWheel,
                          CGEventType(rawValue: 29)!, CGEventType(rawValue: 30)!] {
    let event = fixture(); event.type = type
    require(permittedBrightnessControl(event) == nil, "ordinary keys/mouse/gestures stay blocked")
}
print("PASS: brightness allowlist, modifier shortcuts, malformed events and unrelated input")

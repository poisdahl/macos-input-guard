// SPDX-License-Identifier: MIT
import AppKit
import CoreGraphics

enum BrightnessControl: String, CaseIterable {
    case displayUp = "display_up"
    case displayDown = "display_down"
    case keyboardUp = "keyboard_up"
    case keyboardDown = "keyboard_down"
}

// The four NX_KEYTYPE values and AUX_CONTROL_BUTTONS subtype are defined in
// Apple's public IOKit/hidsystem headers. Do not pass arbitrary systemDefined
// events, ordinary F-keys, or modifier shortcuts (Option-brightness opens Settings).
private struct BrightnessEvent {
    let control: BrightnessControl
    let isRelease: Bool
    let isRepeat: Bool
}

// Also reject the public NX_DEVICE* left/right modifier and stateless Caps Lock
// bits from IOLLEvent.h. These are outside AppKit's device-independent mask.
let brightnessForbiddenFlags = UInt64(NSEvent.ModifierFlags.deviceIndependentFlagsMask
    .subtracting(.function).rawValue) | 0x20ff

private func brightnessEvent(_ event: CGEvent) -> BrightnessEvent? {
    guard event.type.rawValue == NSEvent.EventType.systemDefined.rawValue,
          event.getIntegerValueField(.eventSourceUnixProcessID) == 0,
          let native = NSEvent(cgEvent: event), native.type == .systemDefined,
          native.subtype.rawValue == 8,
          let payload = UInt32(exactly: native.data1) else { return nil }
    let state = (payload >> 8) & 0xff
    let repeatFlag = payload & 0xff
    guard (state == 0x0a && repeatFlag <= 1) || (state == 0x0b && repeatFlag == 0) else { return nil }
    let control: BrightnessControl
    switch payload >> 16 {
    case 2: control = .displayUp
    case 3: control = .displayDown
    case 21: control = .keyboardUp
    case 22: control = .keyboardDown
    default: return nil
    }
    return BrightnessEvent(control: control, isRelease: state == 0x0b, isRepeat: repeatFlag == 1)
}

struct BrightnessDecision {
    let control: BrightnessControl
    let release: Bool
}

struct BrightnessPassthrough {
    private var pressed: Set<BrightnessControl> = []

    // No event posting or settings mutation. The callback forwards the original
    // event; for a paired release only, it clears forbidden modifier flags so a
    // modifier pressed during a hold cannot turn release into a shortcut.
    mutating func decision(for event: CGEvent,
                           currentFlags: () -> CGEventFlags = { [] }) -> BrightnessDecision? {
        guard let lighting = brightnessEvent(event) else { return nil }
        if lighting.isRelease {
            guard pressed.remove(lighting.control) != nil else { return nil }
            return BrightnessDecision(control: lighting.control, release: true)
        }
        // Fn is needed on keyboards configured to use ordinary function keys.
        guard (event.flags.rawValue | currentFlags().rawValue) & brightnessForbiddenFlags == 0 else { return nil }
        if lighting.isRepeat {
            guard pressed.contains(lighting.control) else { return nil }
        } else {
            pressed.insert(lighting.control)
        }
        return BrightnessDecision(control: lighting.control, release: false)
    }
}

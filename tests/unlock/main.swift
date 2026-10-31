// SPDX-License-Identifier: MIT
// Local event fixtures only: no posting, tap, Keychain or physical input.
import Foundation
import CoreGraphics

let code = Array("abcdefgh".utf8)
let keys: [CGKeyCode] = [0, 11, 8, 2, 14, 3, 5, 4]
func event(_ key: CGKeyCode, _ type: CGEventType = .keyDown,
           flags: CGEventFlags = [], pid: Int64 = 0, repeating: Bool = false) -> CGEvent {
    let result = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: type != .keyUp)!
    result.type = type
    result.flags = flags
    result.setIntegerValueField(.eventSourceUnixProcessID, value: pid)
    result.setIntegerValueField(.keyboardEventAutorepeat, value: repeating ? 1 : 0)
    return result
}
func type(_ keys: [CGKeyCode], into entry: inout UnlockCodeEntry, at now: TimeInterval = 1) {
    for key in keys { precondition(!entry.handle(event(key), at: now)) }
}
func released(_ entry: inout UnlockCodeEntry, at now: TimeInterval = 1) -> Bool {
    entry.handle(event(4, .keyUp), at: now)
}

var entry = UnlockCodeEntry(code: code)
type(Array(keys.dropLast()), into: &entry)
type([7, 16, 51, 51, 4], into: &entry) // abcdefgxy, Backspace twice, h
precondition(!entry.handle(event(5, .keyUp), at: 1))
precondition(!entry.handle(event(4, .keyUp, pid: 123), at: 1))
precondition(released(&entry))
print("PASS: overflow corrections preserve prefix; unlock needs final physical key release")

for flag: CGEventFlags in [.maskCommand, .maskControl, .maskAlternate, .maskShift, .maskAlphaShift] {
    entry = UnlockCodeEntry(code: code)
    type(Array(keys.dropLast()), into: &entry)
    precondition(!entry.handle(event(4, flags: flag), at: 1))
    precondition(!released(&entry))
    type(keys, into: &entry)
    precondition(released(&entry))
}
for reset in [event(56, .flagsChanged), event(36)] {
    entry = UnlockCodeEntry(code: code)
    type(Array(keys.dropLast()), into: &entry)
    precondition(!entry.handle(reset, at: 1))
    type([4], into: &entry)
    precondition(!released(&entry))
}
entry = UnlockCodeEntry(code: code)
type(Array(keys.dropLast()), into: &entry)
entry.resetPartial() // A passed brightness event resets partial entry.
type([4], into: &entry)
precondition(!released(&entry))
print("PASS: forbidden modifiers, other keys, modifier changes and brightness reset entry")

for delay in [10.0, 10.01] {
    entry = UnlockCodeEntry(code: code)
    type(Array(keys.dropLast()), into: &entry, at: 1)
    type([4], into: &entry, at: 1 + delay)
    precondition(released(&entry, at: 1 + delay) == (delay == 10))
}
entry = UnlockCodeEntry(code: code)
for key in keys { precondition(!entry.handle(event(key, pid: 123), at: 1)) }
precondition(!released(&entry))
type(Array(keys.dropLast()), into: &entry)
precondition(!entry.handle(event(4, repeating: true), at: 1))
precondition(!released(&entry))
type([4], into: &entry)
precondition(released(&entry))
print("PASS: gap boundary, synthetic input and autorepeat")

entry = UnlockCodeEntry(code: code)
type(Array(repeating: 7, count: 10_000), into: &entry)
type(keys, into: &entry)
precondition(released(&entry))
let longCode = Array(repeating: UInt8(97), count: 63) + [UInt8(98)]
entry = UnlockCodeEntry(code: longCode)
type(Array(repeating: 0, count: 63) + [7, 16, 51, 51, 11], into: &entry)
precondition(entry.handle(event(11, .keyUp), at: 1))
print("PASS: long noise and maximum-length code corrections")

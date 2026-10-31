// SPDX-License-Identifier: MIT
import Foundation
import CoreGraphics

// Event metadata only: this type never posts events or reads a saved code.
struct UnlockCodeEntry {
    private let code: [UInt8]
    private var history: [UInt8] = []
    private var lastKeyTime: TimeInterval = 0
    private var finalKey: Int64?

    init(code: [UInt8]) {
        precondition((8...64).contains(code.count))
        self.code = code
    }

    mutating func resetPartial() { history.removeAll(keepingCapacity: true) }

    // Keep editing history beyond the candidate suffix so Backspace can undo
    // mistakes after a full code's worth of input. History stays bounded.
    mutating func handle(_ event: CGEvent, at now: TimeInterval) -> Bool {
        guard event.getIntegerValueField(.eventSourceUnixProcessID) == 0 else { return false }
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        if event.type == .keyUp { return finalKey == key }
        if event.type == .flagsChanged { resetPartial(); return false }
        guard event.type == .keyDown, finalKey == nil,
              event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return false }
        if now - lastKeyTime > 10 { resetPartial() }
        lastKeyTime = now
        let forbidden: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift, .maskAlphaShift]
        if !event.flags.intersection(forbidden).isEmpty {
            resetPartial()
        } else if key == 51 {
            if !history.isEmpty { history.removeLast() }
        } else if let character = Self.keyCharacters[key] {
            history.append(character)
            if history.count > 128 { history.removeFirst() }
            if history.suffix(code.count).elementsEqual(code) { finalKey = key }
        } else {
            resetPartial()
        }
        return false
    }

    // Physical positions shared by the explicitly supported Apple QWERTY layouts.
    private static let keyCharacters: [Int64: UInt8] = [
        0:97, 1:115, 2:100, 3:102, 4:104, 5:103, 6:122, 7:120, 8:99, 9:118,
        11:98, 12:113, 13:119, 14:101, 15:114, 16:121, 17:116,
        18:49, 19:50, 20:51, 21:52, 22:54, 23:53, 25:57, 26:55, 28:56, 29:48,
        31:111, 32:117, 34:105, 35:112, 37:108, 38:106, 40:107, 45:110, 46:109
    ]
}

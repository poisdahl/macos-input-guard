// SPDX-License-Identifier: MIT
import Foundation

enum GuardInput {
    case keyDown(Int64, repeating: Bool, forbiddenModifiers: Bool)
    case keyUp(Int64)
    case modifiers(held: Bool)
    case buttonDown(Int64)
    case buttonUp(Int64)
}

enum UnlockResult { case blocked, cooldownStarted, unlocked }

// Physical positions shared by the supported Apple QWERTY layouts.
let keyCharacters: [Int64: UInt8] = [
    0:97, 1:115, 2:100, 3:102, 4:104, 5:103, 6:122, 7:120, 8:99, 9:118,
    11:98, 12:113, 13:119, 14:101, 15:114, 16:121, 17:116,
    18:49, 19:50, 20:51, 21:52, 22:54, 23:53, 25:57, 26:55, 28:56, 29:48,
    31:111, 32:117, 34:105, 35:112, 37:108, 38:106, 40:107, 45:110, 46:109
]

struct UnlockSequence {
    private let code: [UInt8]
    private var entered: [UInt8] = []
    private var lastKeyTime: TimeInterval = 0
    private var failures = 0
    private var cooldownUntil: TimeInterval = 0
    private var accepted = false
    private var keys: Set<Int64>
    private var buttons: Set<Int64>
    private var modifiersHeld: Bool

    init(code: [UInt8], keys: Set<Int64> = [], buttons: Set<Int64> = [], modifiersHeld: Bool = false) {
        precondition(!code.isEmpty)
        self.code = code
        self.keys = keys
        self.buttons = buttons
        self.modifiersHeld = modifiersHeld
    }

    var readyToUnlock: Bool { accepted && keys.isEmpty && buttons.isEmpty && !modifiersHeld }

    mutating func consume(_ input: GuardInput, hardwareOrigin: Bool, now: TimeInterval) -> UnlockResult {
        guard hardwareOrigin else { return .blocked }
        switch input {
        case .keyDown(let key, _, _): keys.insert(key)
        case .keyUp(let key): keys.remove(key)
        case .modifiers(let held): modifiersHeld = held; entered.removeAll(keepingCapacity: true)
        case .buttonDown(let button): buttons.insert(button)
        case .buttonUp(let button): buttons.remove(button)
        }
        // Consume all overlapping key/button releases, not only the final code key.
        if accepted { return readyToUnlock ? .unlocked : .blocked }
        guard now >= cooldownUntil else { return .blocked }
        if cooldownUntil != 0 {
            cooldownUntil = 0; failures = 0; entered.removeAll(keepingCapacity: true)
        }
        guard case .keyDown(let key, let repeating, let forbidden) = input, !repeating else { return .blocked }
        if now - lastKeyTime > 10 { entered.removeAll(keepingCapacity: true) }
        lastKeyTime = now
        if forbidden {
            entered.removeAll(keepingCapacity: true)
        } else if key == 51 {
            if !entered.isEmpty { entered.removeLast() }
        } else if let character = keyCharacters[key] {
            entered.append(character)
            if entered.count == code.count {
                if entered == code { accepted = true }
                else {
                    failures += 1
                    entered.removeAll(keepingCapacity: true)
                    if failures >= 5 {
                        cooldownUntil = now + 30
                        entered.removeAll(keepingCapacity: true)
                        return .cooldownStarted
                    }
                }
            }
        } else {
            entered.removeAll(keepingCapacity: true)
        }
        return .blocked
    }
}

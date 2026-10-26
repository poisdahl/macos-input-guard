// SPDX-License-Identifier: MIT
import Foundation

// Pure scheduling state; tap recovery is attempted independently on every loss.
struct FailurePolicy {
    private(set) var pending = false
    private var started: TimeInterval = 0
    private var nextAutomaticAttempt: TimeInterval = 0

    mutating func begin(now: TimeInterval, explicitRequest: Bool = false) -> Bool {
        guard !pending, explicitRequest || now >= nextAutomaticAttempt else { return false }
        pending = true; started = now
        return true
    }

    mutating func complete(accepted: Bool, now: TimeInterval) {
        pending = false
        // An accepted action is still unconfirmed. Keep filtering, but don't
        // repeatedly lock the user as they log back in. Explicit signals retry.
        nextAutomaticAttempt = accepted ? .infinity : now + 15
    }

    func defersCodeUnlock(now: TimeInterval) -> Bool {
        pending && now - started < 5
    }
}

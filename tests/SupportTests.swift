// SPDX-License-Identifier: MIT
import Foundation
import Darwin

func require(_ condition: @autoclosure () -> Bool, _ name: String) {
    if !condition() { fputs("FAIL: \(name)\n", stderr); exit(1) }
}

@main struct SupportTests {
    static let code = Array("correct12".utf8)
    static let positions = Dictionary(uniqueKeysWithValues: keyCharacters.map { ($1, $0) })
    static func type(_ text: String, into decoder: inout UnlockSequence, at time: TimeInterval, hardware: Bool = true) -> UnlockResult {
        var result = UnlockResult.blocked
        for byte in text.utf8 {
            let key = positions[byte]!
            let down = decoder.consume(.keyDown(key, repeating: false, forbiddenModifiers: false), hardwareOrigin: hardware, now: time)
            if down == .cooldownStarted { result = down }
            let up = decoder.consume(.keyUp(key), hardwareOrigin: hardware, now: time)
            if up == .unlocked { result = up }
        }
        return result
    }

    static func main() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.first == "logger" {
            let output = StatusOutput()
            for _ in 0..<10000 { output.report(String(repeating: "x", count: 1024)) }
            output.flush()
            return
        }
        if args.first == "hold-lock" || args.first == "try-lock" {
            do {
                let instance = try BlockingInstance(path: args[1])
                withExtendedLifetime(instance) {
                    if args[0] == "hold-lock" {
                        print("READY"); fflush(stdout)
                        while true { pause() }
                    }
                }
            } catch { exit(2) }
            return
        }
        var decoder = UnlockSequence(code: code)
        require(type("correct12", into: &decoder, at: 1) == .unlocked, "correct code")
        decoder = UnlockSequence(code: code)
        require(type("correct12", into: &decoder, at: 1, hardware: false) == .blocked, "synthetic origin ignored")
        require(type("correct12", into: &decoder, at: 2) == .unlocked, "physical code after synthetic input")

        decoder = UnlockSequence(code: code)
        _ = type("cor", into: &decoder, at: 1)
        _ = decoder.consume(.keyDown(51, repeating: false, forbiddenModifiers: false), hardwareOrigin: true, now: 2)
        _ = decoder.consume(.keyUp(51), hardwareOrigin: true, now: 2)
        require(type("rrect12", into: &decoder, at: 3) == .unlocked, "backspace correction")

        decoder = UnlockSequence(code: code)
        _ = type("cor", into: &decoder, at: 1)
        require(type("rect12", into: &decoder, at: 12) == .blocked, "idle timeout clears partial")
        _ = decoder.consume(.modifiers(held: true), hardwareOrigin: true, now: 13)
        _ = decoder.consume(.modifiers(held: false), hardwareOrigin: true, now: 13)
        require(type("correct12", into: &decoder, at: 14) == .unlocked, "modifier reset")

        decoder = UnlockSequence(code: code)
        for byte in code {
            let key = positions[byte]!
            _ = decoder.consume(.keyDown(key, repeating: true, forbiddenModifiers: false), hardwareOrigin: true, now: 1)
            require(decoder.consume(.keyUp(key), hardwareOrigin: true, now: 1) == .blocked, "autorepeat ignored")
        }
        require(type("correct12", into: &decoder, at: 2) == .unlocked, "fresh presses after repeats")

        // Last code key releases before an earlier code key and a mouse button.
        decoder = UnlockSequence(code: code)
        _ = decoder.consume(.buttonDown(0), hardwareOrigin: true, now: 1)
        _ = type("correct", into: &decoder, at: 1)
        let one = positions[49]!, two = positions[50]!
        _ = decoder.consume(.keyDown(one, repeating: false, forbiddenModifiers: false), hardwareOrigin: true, now: 1)
        _ = decoder.consume(.keyDown(two, repeating: false, forbiddenModifiers: false), hardwareOrigin: true, now: 1)
        require(decoder.consume(.keyUp(two), hardwareOrigin: true, now: 1) == .blocked, "overlapping earlier key remains blocked")
        require(decoder.consume(.keyUp(one), hardwareOrigin: true, now: 1) == .blocked, "held mouse button remains blocked")
        require(decoder.consume(.buttonUp(0), hardwareOrigin: true, now: 1) == .unlocked, "last held input release consumed")

        decoder = UnlockSequence(code: code, keys: [40], buttons: [1], modifiersHeld: true)
        require(type("correct12", into: &decoder, at: 1) == .blocked, "initially held inputs delay unlock")
        _ = decoder.consume(.keyUp(40), hardwareOrigin: true, now: 1)
        _ = decoder.consume(.buttonUp(1), hardwareOrigin: true, now: 1)
        require(decoder.consume(.modifiers(held: false), hardwareOrigin: true, now: 1) == .unlocked, "initial modifier release consumed")

        decoder = UnlockSequence(code: code)
        require(type("xxxxxxxxx", into: &decoder, at: 1) == .blocked, "one incorrect complete attempt")
        require(type("correct12", into: &decoder, at: 2) == .unlocked, "immediate correct retry after one incorrect attempt")
        decoder = UnlockSequence(code: code)
        for attempt in 1...4 {
            require(type("xxxxxxxxx", into: &decoder, at: Double(attempt)) == .blocked, "first four attempts do not start cooldown")
        }
        require(type("xxxxxxxxx", into: &decoder, at: 5) == .cooldownStarted, "exact fifth incorrect attempt starts cooldown")
        require(type("correct12", into: &decoder, at: 6) == .blocked, "correct code ignored during cooldown")
        _ = decoder.consume(.modifiers(held: false), hardwareOrigin: true, now: 6)
        require(type("correct12", into: &decoder, at: 34) == .blocked, "modifiers do not reset cooldown")
        require(type("correct12", into: &decoder, at: 36) == .unlocked, "code works after cooldown")

        // A key released before the post-registration snapshot is not seeded;
        // a queued release for a seeded held key is safely reconciled.
        decoder = UnlockSequence(code: code, keys: [])
        _ = decoder.consume(.keyUp(40), hardwareOrigin: true, now: 1)
        require(type("correct12", into: &decoder, at: 2) == .unlocked, "startup release before snapshot")
        decoder = UnlockSequence(code: code, keys: [40])
        _ = decoder.consume(.keyUp(40), hardwareOrigin: true, now: 1)
        require(type("correct12", into: &decoder, at: 2) == .unlocked, "startup release queued after snapshot")

        var policy = FailurePolicy()
        require(policy.begin(now: 1), "first fault starts fallback")
        require(!policy.begin(now: 2, explicitRequest: true), "only one fallback worker")
        require(policy.defersCodeUnlock(now: 5), "short fallback attempt defers unlock")
        require(!policy.defersCodeUnlock(now: 7), "hung fallback cannot indefinitely prevent owner unlock")
        policy.complete(accepted: false, now: 8)
        require(!policy.begin(now: 22), "failed fallback retry is rate limited")
        require(policy.begin(now: 23), "persistent fault retries after cooldown")
        policy.complete(accepted: false, now: 24)
        require(policy.begin(now: 25, explicitRequest: true), "explicit signal can retry failure")
        policy.complete(accepted: true, now: 26)
        require(!policy.begin(now: 1000), "accepted request avoids repeated automatic lock on login")
        require(policy.begin(now: 1001, explicitRequest: true), "explicit signal can retry accepted request")

        decoder = UnlockSequence(code: code)
        policy = FailurePolicy()
        require(policy.begin(now: 1), "pending fallback before owner code")
        _ = type("correct12", into: &decoder, at: 2)
        require(decoder.readyToUnlock && policy.defersCodeUnlock(now: 2), "owner unlock remembered during request")
        require(decoder.readyToUnlock && !policy.defersCodeUnlock(now: 7), "owner unlock becomes ready with no extra physical event")
        print("PASS: unlock, source rejection, cooldown and overlapping input release.")
    }
}

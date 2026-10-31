// SPDX-License-Identifier: MIT
// Injected lookup/press and clock: NEVER instantiates ScreenLocker or calls AX.
import Foundation
import ApplicationServices

var time: TimeInterval = 0
var lookups = 0
var presses = 0
let recovered = ScreenLockRequest.run(lookup: { deadline -> Int? in
    precondition(deadline == 8)
    lookups += 1
    time += 0.2 // A reply slower than the old 150 ms limit.
    return lookups == 2 ? 1 : nil
}, press: { _ in presses += 1; return .accepted }, now: { time }, pause: { time += $0 })
precondition(recovered == .accepted && lookups == 2 && presses == 1)

for result: ScreenLockResult in [.accepted, .unconfirmed(-25204), .rejected(-25202)] {
    presses = 0
    let actual = ScreenLockRequest.run(lookup: { _ in 1 }, press: { _ in presses += 1; return result },
                                       now: { 0 }, pause: { _ in fatalError("Press must not retry") })
    precondition(actual == result && presses == 1)
}
precondition(ScreenLockRequest.result(for: .cannotComplete) == .unconfirmed(AXError.cannotComplete.rawValue))
precondition(ScreenLockRequest.result(for: .success) == .accepted)
precondition(ScreenLockRequest.result(for: .actionUnsupported) == .rejected(AXError.actionUnsupported.rawValue))
print("PASS: lookup retries, ambiguous AX result and exactly one press")

time = 0; presses = 0; lookups = 0
let unavailable = ScreenLockRequest.run(lookup: { _ -> Int? in lookups += 1; return nil },
    press: { _ in presses += 1; return .accepted }, now: { time }, pause: { time += $0 })
precondition(unavailable == .unavailable && time == 8 && lookups < 100 && presses == 0)
time = 0
let late = ScreenLockRequest.run(lookup: { _ in time = 8.2; return 1 },
    press: { _ in presses += 1; return .accepted }, now: { time }, pause: { time += $0 })
precondition(late == .unavailable && presses == 0)
print("PASS: shared discovery deadline and no late press")

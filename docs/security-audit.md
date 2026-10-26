# Security audit — 2026-10-26

This review uses the intended threat model: limited protection against deliberate
unauthorized keyboard/mouse use while a compatible computer-use session keeps
working. It is not a certification of resistance to all physical attacks.

Three independent agent reviewers inspected the source, packaging and failure
behavior. Repairs were reviewed again and exercised through isolated tests
using the actual support code. No live keyboard blocking, Keychain access,
permission changes, logout or reboot was part of the automated audit.

## Findings and repairs in the 0.2.0 candidate

| Finding | Repair and verification |
| --- | --- |
| Synchronous stdout could stall the tap or kill the process through SIGPIPE. Closed-pipe termination was reproduced with the 0.1.0 help command. | Bounded background status output, handled write errors and ignored SIGPIPE. Closed/full-pipe subprocess regressions pass without a tap. |
| Unlock released filtering on the final code key-up while another key/button could remain held. | Track held inputs and consume their releases before removing filtering. Interleaved key/button and startup-release regressions pass. |
| Code guesses were unlimited. | Five incorrect complete entries impose a 30-second cooldown while blocking continues. Wrong-then-correct, exact threshold and cooldown-reset tests pass. |
| Two blocking instances could swallow each other's unlock input. | One OS-held per-user advisory lock, acquired before code prompts. Contention, process-death recovery and symlink rejection tests pass. Older versions do not participate. |
| A non-null tap could have lost required event-mask bits, and preflight could become stale during prompts. | Recheck readiness and verify the registered requested event mask before reporting armed. This does not prove coverage of other macOS input paths. |
| Unlimited runs retained unnecessary counters per source process. | A scalar count in code-lock mode; diagnostic counters capped at 256 pairs. |
| Detected faults immediately exposed the unlocked desktop. | Attempt tap recovery and the system Finder's Lock Screen action. Keep remaining filtering even after action acceptance. Isolated scheduling tests cover retries, one pending request and deferred owner unlock. |
| Installation could race a guard started during the build. | Repeat the running-process check immediately before replacement. This check is not an atomic exclusion against arbitrary concurrent installation/startup. |

Review also caught and corrected issues in the candidate: overlapping windows
counted as separate guesses, held-state sampling before interception, a throwing
initializer that could close its descriptor twice, a permanently latched fault,
and code unlock waiting for an unnecessary extra event during fallback.

## Validation boundary

`tests/smoke.sh` and `tests/security.sh` exercise command validation and the
actual isolated logger, decoder, instance-lock and failure-scheduling helpers.
CI runs both suites on Intel and Apple Silicon. No CI job invokes a real lock.
The read-only `check-lock` command has found the intended Finder menu action on
the initial Intel test machine; availability is not proof that the action locks.

**The changed runtime still requires supervised qualification before release or
installation.** Verify `test-screen-lock`, normal macOS login, a bounded physical
input/code-unlock test, and a fault-triggered lock with remaining filtering.
Repeat the same pre-existing native Codex session test. Historical successful
physical tests documented in [compatibility](compatibility.md) apply to 0.1.0.

## Remaining limits

A one-process input filter cannot promise protection after its own crash,
SIGKILL, suspension or event-loop stall. Events may escape before tap-loss
recovery or before macOS locks. Secure Input can withhold keyboard events and
lost Accessibility permission can also prevent the lock request. AX action
acceptance does not confirm the screen's lock state.

Missed key/button releases during Secure Input or tap loss can leave conservative
held-input state after login. This may require pressing/releasing that input or
explicit recovery; automatic state reconciliation has not been qualified and
must not prematurely release queued events. Include this in the supervised
fault/recovery test.

The fallback currently supports only the system Finder's English **Lock Screen**
menu with the default Control-Command-Q shortcut. After an accepted fallback,
automatic requests are suppressed for that run to avoid relocking during login;
end it with the code after login and start a fresh guard if needed.

Unintercepted gestures, media keys, alternate assistive/remote paths and malicious
hardware need separate supervised investigation. No new hardware-only bypass
was demonstrated by this audit. Screen contents remain visible. Same-user
malicious processes remain outside the protection claim. See [SECURITY.md](../SECURITY.md).

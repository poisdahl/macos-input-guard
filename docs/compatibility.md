# Compatibility and manual verification

Input Guard was built for a specific need: keep an existing computer-use
session working while ordinary physical input is blocked. It does not move an
agent to another desktop, start a replacement session or unlock macOS.

## What is known

| Setup or path | Evidence |
| --- | --- |
| Native Codex computer use on an Intel Mac | A pre-existing Calculator binding continued clicking and typing during a supervised physical-input trial. |
| Apple Silicon | Native build/CLI CI is configured. Physical blocking, code unlock and agent continuity need a manual check on this architecture. |
| Claude Code-based computer-use setups | Not tested. The particular computer-use backend determines whether its input reaches this tap. |
| Other desktop agents, remote desktop, remappers and assistive input | Not tested. Use a bounded trial before relying on the guard. |
| Events delivered through the guarded session tap | Dropped while blocking, including synthetic events. There is no trusted-agent allowlist. |
| Browser DOM/API automation | Not validated here. Success with DOM automation does not prove native mouse/keyboard compatibility. |

During the native Codex observation, its test actions did not appear at the
session tap. That is evidence for this tested route bypassing the tap, not a
guarantee about every Codex feature, release or automation backend. A physical
input detector elsewhere in another agent could still pause that agent even
when its target application receives no physical input.

## Manual test procedure

The 0.2.0 hardening changes need a fresh supervised test; the historical results
below describe 0.1.0. First use `check-lock`, then, when ready for a real macOS
lock, `test-screen-lock`. Verify the login screen yourself and unlock normally
before starting the computer-use continuity test. The fallback currently needs
an English macOS interface and Finder's default Lock Screen shortcut.

During a later supervised timed `lock` test, TERM from another session should
request macOS locking while keeping remaining filtering. Verify that normal
macOS login is possible, then enter the guard code and release held inputs.
A failed fallback is a failed test, even if ordinary keyboard blocking works.


Use a harmless application and save unrelated work first. Do not begin with an
unlimited lock. Run only one blocking instance at a time.

1. Start the actual computer-use session you intend to use. Have it perform a
   simple operation in Calculator or another disposable target.
2. Optionally run `input-guard observe 15`. Move the physical pointer and press
   and release Shift. Confirm that the observer counts those events; it does
   not record characters. Check the agent's actions too.
3. Run `input-guard trial 15`. Its startup output must say the tap is enabled.
4. During those 15 seconds, attempt harmless physical movement, clicks and
   typing. At the same time, have the **same existing session** perform another
   operation. Verify the result while the guard is still active, not from a
   screenshot taken only after expiry.
5. Confirm that input is restored after expiry and the agent did not pause due
   to physical-input detection.
6. Run `input-guard lock 60` and validate typed-code unlock before the deadline.
   If using a saved code, first run `set-code` yourself and verify the lock says
   it is using the saved code. Never share the code in a bug report.
7. Only after these checks, use `input-guard lock` for an unlimited run. Keep
   the printed PID and a working way to terminate it from another session.

Repeat after significant macOS, agent, input-device or input-method changes.
Do not infer support for media keys, global shortcuts or multitouch gestures
from an ordinary typing-and-clicking test.

## Initial manual evidence

The initial Intel desktop test on 2026-10-26 counted 258 physical events during
a 30-second guard. The user confirmed ordinary keyboard and mouse input was
blocked and restored. The same pre-existing native Codex Calculator binding
completed two arithmetic operations while the tap remained active, including
after physical attempts, without pausing.

Additional checks covered temporary-code unlock, saved-code reuse from the
local Keychain, finite expiry, and an unlimited invocation terminated by a
separate bounded test harness. These are limited functional observations, not
an adversarial security assessment or certification of other agents.

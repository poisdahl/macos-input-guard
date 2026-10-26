# Compatibility and manual verification

Input Guard was built for a specific need: keep an existing computer-use
session working while ordinary physical input is blocked. It does not move an
agent to another desktop, start a replacement session or unlock macOS.

## What is known

| Setup or path | Evidence |
| --- | --- |
| Native Codex computer use on an Intel Mac | A pre-existing Calculator binding continued clicking and typing during a supervised physical-input trial. |
| Mission Control trackpad swipe on the tested Intel Mac | Blocked by the 0.1.2 all-events filter; the owner confirmed normal input returned after the 30-second trial. Other gestures and setups need their own test. |
| Apple Silicon | Native build/CLI CI is configured. Physical blocking, code unlock and agent continuity need a manual check on this architecture. |
| Claude Code-based computer-use setups | Not tested. The particular computer-use backend determines whether its input reaches this tap. |
| Other desktop agents, remote desktop, remappers and assistive input | Not tested. Use a bounded trial before relying on the guard. |
| Events delivered through the guarded session tap | Dropped while blocking, including synthetic events. There is no trusted-agent allowlist. |
| Browser DOM/API automation | Not validated here. Success with DOM automation does not prove native mouse/keyboard compatibility. |

The tested Calculator actions still reached the application while filtering
was active. This does not mean that every event from Codex bypasses the tap:
the 0.1.2 trial also intercepted two null events from its computer-use service.
Compatibility is not guaranteed for every Codex feature, release or backend. A physical
input detector elsewhere in another agent could still pause that agent even
when its target application receives no physical input.

## Manual test procedure

Use a harmless application and save unrelated work first. Do not begin with an
unlimited lock. Run only one blocking instance at a time.

1. Start the actual computer-use session you intend to use. Have it perform a
   simple operation in Calculator or another disposable target.
2. Optionally run `input-guard observe 15`. Move the physical pointer and press
   and release Shift. Confirm that the observer counts those events; it does
   not record characters. Check the agent's actions too.
3. Run `input-guard trial 15`. Its startup output must say the tap is enabled
   and reports the actual registered event mask. The mask alone does not prove
   that every physical input path is intercepted.
4. During those 15 seconds, attempt harmless physical movement, clicks and
   typing. Try the Mission Control swipe and any other gestures you rely on
   blocking. At the same time, have the **same existing session** perform another
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

## Mission Control qualification in 0.1.2

On 2026-10-26, on an Intel Mac (`x86_64`) running macOS 15.8.1, a passive
all-events session tap reported mask `0xffffffff`.
Pointer and Shift positive controls worked. The owner repeatedly opened and
closed Mission Control during a separate gesture phase. That phase included
raw event type 30, which the earlier explicit event list omitted. Raw event
numbers are observations, not a claimed mapping to AppKit gesture constants.

A separate 30-second all-events blocking trial reported the same registered
mask and remained enabled. It intercepted 3,527 hardware/system events,
including types 29 and 30, plus two null events from the computer-use service.
The owner confirmed Mission Control swipes and ordinary input were blocked and
returned normally after expiry. The same pre-existing native Calculator binding
computed `731 + 269 = 1000` and `17 × 19 = 323` before expiry, including after
physical attempts. Saved-code unlock with this expanded mask is still awaiting
the owner's separate Terminal test.

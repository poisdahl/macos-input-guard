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
| Claude Desktop 4.29.0, Code tab, Background, Haiku 5.5 Low on Intel/macOS 15.8.1 | Existing Calculator session continued during a full 60-second trial with the privacy overlay and physical input attempts. See the comparison below. Claude CLI and Full control with Input Guard remain untested. |
| Other desktop agents, remote desktop, remappers and assistive input | Not tested. Use a bounded trial before relying on the guard. |
| Events delivered through the guarded session tap | Dropped while blocking, including synthetic events, except the four brightness controls in 0.3.0. There is no trusted-agent allowlist. |
| Browser DOM/API automation | Not validated here. Success with DOM automation does not prove native mouse/keyboard compatibility. |

Version 0.2.0 also passed bounded overlay and crash/hang recovery tests on the
same Intel/macOS 15.8.1 setup, including physical takeover after a Codex curtain.
See [privacy and recovery evidence](privacy-and-recovery.md#test-results-in-020) for
the exact scope and limitations.

The tested Calculator actions still reached the application while filtering
was active. This does not mean that every event from Codex bypasses the tap:
the 0.1.2 trial also intercepted two null events from its computer-use service.
Compatibility is not guaranteed for every Codex feature, release or backend. A physical
input detector elsewhere in another agent could still pause that agent even
when its target application receives no physical input.

## Claude and native macOS locking — 2026-10-28

On one Intel Mac running macOS 15.8.1, using Claude Desktop 4.29.0's Code tab,
Background mode and Haiku 5.5 Low, an existing Calculator session continued
through Input Guard `0.2.0+failure-default-dev` (the 0.3.0 candidate).

A 60-second `trial --privacy` intercepted 1,535 hardware/system events. The owner
confirmed that typing, pointer/clicks and Mission Control stayed blocked
throughout, then normal input returned and the overlay disappeared. Claude's
native background tools calculated `683 - 247 = 436` near the start and
`29 × 17 = 493` later in the minute. Both fresh screenshots/results completed
before guard expiry. The guard reported normal timed completion and no Secure
Input activation. Codex made no computer-use calls during the trial.

A preceding 60-second repeat also completed normally with two native Calculator
results, but recorded no physical events; it verifies automation continuity, not
a second physical-blocking qualification. An earlier attempt ended after 16 seconds with a protection-lost
message; the owner reported a system password dialog. The cause was not
isolated. This is not evidence that such interruptions are harmless: default
`lock` attempts native locking after a fault; unsupervised `trial` releases input.

For comparison, with Input Guard off and Codex idle during the locked interval:

| Claude path | Native macOS-lock result |
| --- | --- |
| Same Background session, two separate tests | First Calculator click rejected with “The screen is locked”; no calculation entered. In the repeat, app screenshot capture still worked. |
| Same session switched to Full control | Unlocked baseline worked; while locked, full-screen capture returned nil and no clicks ran. Capture worked again after owner authentication without permission changes. The generic capture error does not establish its unique cause. Background mode was restored afterward. |

The owner confirmed the instructed locked intervals and normal authentication.
These tests establish the observed Calculator behavior, not universal agent
support or protection against determined physical access. Claude Full control
with Input Guard, Claude CLI, other apps/backends, and Claude-specific recovery
from guard faults remain unqualified. Code unlock and recovery have separate
earlier tests; these Claude trials did not repeat them.

Native macOS locking also worked in separate native Codex Calculator tests on
this Mac, both for an existing binding and a fresh binding after locking. An
uninterrupted run through one existing binding completed seven calculations
while the owner confirmed the Mac stayed locked and authentication remained
required. Input Guard may therefore be unnecessary for that Codex setup.

## Manual test procedure

Use a harmless application and save unrelated work first. Release all keys and
buttons before arming; a brightness key already held at activation is not
physically qualified. Do not begin with an unlimited lock. Run only one blocking instance at a time.

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

## Brightness-controls test

Available since 0.3.0. First run `observe 30`, pressing display brightness down/up and
keyboard backlight down/up without other modifiers. Check that the four
`brightness_control` categories appear; observation does not block input.

Then run a bounded `trial 30 --privacy`: confirm the actual display and keyboard
lighting changes, not only an on-screen indicator. Keep levels above zero and
restore their previous levels with the opposite buttons. Check that ordinary
typing, pointer input and Mission Control remain blocked, and that Option plus
either brightness button does not open Settings. If Fn is needed for the media
function, test that too. Also check a modifier pressed during a held brightness
key: the release must end the adjustment without opening Settings. In a separate
bounded trial, hold Option before arming, release it during the trial, then try
brightness; Settings must not open (brightness may stay blocked if macOS still
reports a modifier). Verify existing agent continuity, automatic expiry and
saved-code unlock before relying on the candidate.

### Brightness-only candidate evidence

For `0.2.0+brightness-dev` on the same Intel Mac, the owner confirmed that both display brightness and
keyboard backlight changed during a passive check and a subsequent 30-second
`trial 30 --privacy`. During the blocking trial, ordinary typing, pointer/clicks
and Mission Control stayed blocked; the overlay disappeared and normal input
returned at expiry. The existing native Codex Calculator session continued
working, calculating `731 + 269 = 1000` while the trial was active.

The trial counted 937 events, including 63 passed lighting events across all four
controls. This is not a count of blocked events.

In a separate 30-second trial, the owner confirmed that Option plus the lighting
buttons did not open Settings, adjustment stopped after releasing a held button
with Option pressed during the hold, and normal input returned at expiry. The
existing Codex Calculator session calculated `84 + 16 = 100` during that trial.

With Option held before arming, the owner confirmed that Settings stayed closed
after releasing Option and trying the lighting buttons. Lighting remained
blocked until the trial expired, and normal input returned afterward. The tap
recorded one modifier event and 92 lighting events, with no lighting passthrough.
This is consistent with a retained modifier state; release modifier keys before
starting the guard for normal lighting control.

After the candidate was rebuilt in a durable checkout, the owner completed
`lock 60 --privacy` in Terminal and confirmed lighting control, saved-code unlock
before expiry, overlay removal and restored normal input. These observations do
not establish support for other hardware or physically qualify the later
default-failure-locking candidate. The [October 28 tests above](#claude-and-native-macos-locking--2026-10-28)
qualify Claude Background continuity and timed expiry, not crash recovery.

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
physical attempts. In a separate Terminal-launched `lock 60` run, the owner
confirmed that the Mission Control swipe remained blocked and the saved code
unlocked the guard before the deadline.

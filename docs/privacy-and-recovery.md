# Screen overlay and crash recovery

Since 0.3.0, `lock` enables failure recovery by default; privacy remains opt-in.
Release 0.2.0 requires explicit `--lock-on-failure`. Check
`input-guard --version` and validate timed runs before unlimited use. Installation
is described in the [README](../README.md).

## Frosted overlay

```sh
input-guard preview 20             # Overlay only; input stays usable
input-guard trial 20 --privacy     # Overlay and a timed input filter
input-guard lock 60 --privacy      # Test code unlock with the overlay
```

The overlay uses a native AppKit material in a nonactivating, click-through panel
on each detected display. It does not capture images or require Screen Recording
permission. macOS Reduce transparency makes the material opaque; the guard
respects that preference rather than changing it.
For `lock`, it shows “Input Guard is active. Type your Input Guard code to release. No Enter
needed.” There is no password field or visible code-entry progress. Code entry
still belongs to the input filter; this is not a macOS login screen.

The frosted material obscures the desktop but does **not guarantee that text or
other content is unreadable**. Appearance and accessibility settings affect the
result; large text and shapes may remain recognizable. The guard does not
change those settings. Display changes rebuild the panels, which can expose
frames during the transition. It does not prevent screenshots or recording.

App/window-specific capture can see an application behind the overlay. A
whole-display capture normally sees the overlay too. Test the exact existing
agent session you intend to use; a successful browser DOM action does not prove
native screenshot/input compatibility. Do not depend on capture-exclusion APIs.

## Native lock fallback

```sh
input-guard lock 60 --privacy
```

`lock` starts one temporary supervisor and one guard worker. There
is no persistent daemon, login item or automatic restart. Only the worker reads
the code and owns the event filter and overlay. Their private inherited control
channel carries lifecycle messages, never the code. Both processes retain the
same blocking-instance reservation until their work ends.

After preflight/code entry, the supervisor arms before the event filter is
created. Cancellation or refusal during code/preflight checks does not request locking.
After an arming attempt, an orphaned worker conservatively requests locking on
a controlled failure, including a lost acknowledgement. A setup failure
**after** arming also requests locking, even if startup
never reached the `BLOCKING` message.

On an unexpected worker exit (including SIGKILL), lost interception, or a stale
event-loop heartbeat, the supervisor terminates and reaps its own worker.
**Only after the worker's filter and windows are gone** does it request the
system Finder's Lock Screen action. A responsive worker can also detect that
its supervisor has died, remove its own filter/windows, and request locking.
Controlled local faults and post-arm setup failures also check parent death
after teardown, so they do not skip recovery while exiting as an orphan.
Each path makes one request; it does not restart protection or repeatedly lock.

Accepted code unlock and the explicitly selected timed expiry are normal
releases. They do not request macOS locking. **Terminating a supervised guard
is a fault and requests native locking**. `--no-lock-on-failure` explicitly
disables supervision; failures then release input without macOS authentication.
`trial` remains unsupervised unless `--lock-on-failure` is explicit.
The supervisor reports both process IDs. The fallback currently requires the
validated English “Lock Screen” menu item and Accessibility access; it refuses
to start if that action cannot be found. Finder must remain available.

This is **best effort, not fail-closed security**:

- There is a gap between losing/removing interception and macOS locking.
- Accessibility accepting the action does not prove the Mac is locked. The
  output explicitly reports “lock state unconfirmed.”
- The request can fail, time out or be interrupted. Both processes being
  killed/frozen, OS failure or deliberate same-user interference are not covered.
- A supervisor dying immediately after the worker checks ownership can still
  escape detection during shutdown. This is not a guarantee of recovery from
  simultaneous failures.
- There is no automatic retry after a failed request. Normal macOS protection
  and restart/login settings remain independent of Input Guard.
- Codex Locked use may show its own curtain while temporarily using the Mac.
  Input Guard must be gone so local input can reach that curtain's takeover
  behavior. An active agent can change what the screen shows after a request.

## Qualification

Keep recovery access from another device. Run one guard at a time and save
unrelated work before supervised tests.

1. Start the actual agent session in Calculator. Run `preview 20`. Check every
   physical display, text legibility, full-screen apps and focus. Obtain a fresh
   target-app screenshot and result through the same agent while it is active.
2. Run `trial 20 --privacy`; verify physical typing, pointer and Mission Control
   are blocked, the same agent works, and the overlay/filter disappear on time.
3. Run `lock 60 --privacy` yourself, handle any Keychain prompt,
   and verify the saved code releases everything before expiry without locking.
4. Coordinate separate bounded worker-crash and worker-hang tests. Confirm the
   worker has ended before the native-lock request. If a Codex curtain appears,
   verify physical takeover reaches normal macOS authentication, then verify
   there is no second automatic lock after login.

Only a person at the Mac can confirm the physical privacy and authentication
checks. A successful AX request or agent screenshot alone is insufficient.
Stop after any recovery failure; do not repeat unlimited tests.

### Test results in 0.2.0

On one Intel Mac running macOS 15.8.1 with one display, the native overlay and
30-second input trial passed: the owner confirmed that typing, pointer input and
Mission Control were blocked, then returned to normal. An existing native Codex
Calculator session continued to calculate and capture the app during the trial.
The owner also confirmed that the saved code released the overlay and filter
with `--lock-on-failure` enabled, without activating the macOS lock.

Separate bounded worker-crash and worker-hang tests also passed. In each, the
supervisor reported that its worker had ended before making one accepted
native-lock request. The owner confirmed normal macOS login and restored input,
with no second automatic lock. In an additional crash test, a screenshot request
through the same existing Calculator binding succeeded after the native-lock
request. The owner saw the Codex curtain and confirmed that dismissing it, normal
macOS login and subsequent input all worked, without a second lock.
These observations do not establish unreadable screen content, multi-display
coverage or compatibility with other capture backends or agents.

These physical crash/hang and code-unlock observations apply to 0.2.0. The
0.3.0 candidate's default-failure recovery changes passed automated tests but
were not physically requalified on this candidate. Its later Claude trials qualify
[normal input blocking and timed expiry](compatibility.md#claude-and-native-macos-locking--2026-10-28).

Automated `tests/supervisor.sh` requires Python 3.9+ and uses test workers and a
substitute lock callback. The deployed executable does not require Python.
It does not block input, read Keychain or invoke a real lock. It exercises normal
completion, preflight failure, unexpected exits, crashes, stopped workers,
stale/closed channels, delayed acknowledgements, stalled output, supervisor
death and continued instance ownership.

## Implementation references

- [Apple: nonactivating overlays across Spaces](https://developer.apple.com/forums/thread/826308)
- [Apple: independent window capture despite occlusion](https://developer.apple.com/videos/play/wwdc2022/10155/)
- [OpenAI: Locked use and local takeover](https://learn.chatgpt.com/docs/computer-use#locked-use)

These describe API behavior and design constraints, not certification of this
implementation or universal agent compatibility.

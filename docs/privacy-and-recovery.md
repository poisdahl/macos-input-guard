# Experimental screen overlay and crash recovery

These options are under qualification. They are not included in the installed
0.1.2 release and do not change the behavior of an ordinary `lock` invocation.
Do not replace a working installation until the checks below pass on your Mac.

## Frosted overlay

```sh
input-guard preview 20             # Overlay only; input stays usable
input-guard trial 20 --privacy     # Overlay and a timed input filter
input-guard lock 60 --privacy      # Test code unlock with the overlay
```

The overlay uses a nonactivating, click-through panel on each detected display.
It shows “Input Guard is active. Type your Input Guard code to release. No Enter
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
input-guard lock 60 --privacy --lock-on-failure
```

`--lock-on-failure` starts one temporary supervisor and one guard worker. There
is no persistent daemon, login item or automatic restart. Only the worker reads
the code and owns the event filter and overlay. Their private inherited control
channel carries lifecycle messages, never the code. Both processes retain the
same blocking-instance reservation until their work ends.

After preflight/code entry, the supervisor arms before the event filter is
created. Cancellation or refusal before arming does not request locking. A
setup failure **after** arming conservatively requests locking, even if startup
never reached the `BLOCKING` message.

On an unexpected worker exit (including SIGKILL), lost interception, or a stale
event-loop heartbeat, the supervisor terminates and reaps its own worker.
**Only after the worker's filter and windows are gone** does it request the
system Finder's Lock Screen action. A responsive worker can also detect that
its supervisor has died, remove its own filter/windows, and request locking.
Each path makes one request; it does not restart protection or repeatedly lock.

Accepted code unlock and the explicitly selected timed expiry are normal
releases. They do not request macOS locking. **Terminating a supervised guard
is a fault and requests native locking**, unlike the plain 0.1.2 release path.
The supervisor reports both process IDs. The fallback currently requires the
validated English “Lock Screen” menu item and Accessibility access; it refuses
to start if that action cannot be found. Finder must remain available.

This is **best effort, not fail-closed security**:

- There is a gap between losing/removing interception and macOS locking.
- Accessibility accepting the action does not prove the Mac is locked. The
  output explicitly reports “lock state unconfirmed.”
- The request can fail, time out or be interrupted. Both processes being
  killed/frozen, OS failure or deliberate same-user interference are not covered.
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
3. Run `lock 60 --privacy --lock-on-failure` yourself, handle any Keychain prompt,
   and verify the saved code releases everything before expiry without locking.
4. Coordinate separate bounded worker-crash and worker-hang tests. Confirm the
   worker has ended before the native-lock request. If a Codex curtain appears,
   verify physical takeover reaches normal macOS authentication, then verify
   there is no second automatic lock after login.

Only a person at the Mac can confirm the physical privacy and authentication
checks. A successful AX request or agent screenshot alone is insufficient.
Stop after any recovery failure; do not repeat unlimited tests.

Automated `tests/supervisor.sh` uses test workers and a substitute lock callback.
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

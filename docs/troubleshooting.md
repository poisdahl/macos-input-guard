# Troubleshooting

## Permission or event-tap creation failure

Run `input-guard probe` from the same Terminal or application you will use to
start the guard. Accessibility permission can be attributed to the executable
or its launching application. Permission in one launch context does not prove
permission in another.

Grant the intended entry in System Settings → Privacy & Security →
Accessibility, then rerun the command. Do not edit the TCC database or disable
System Integrity Protection. Installation itself does not grant permissions.

## Secure Input is active

macOS Secure Input prevents reliable keyboard interception. Finish any password
entry that is currently active and inspect the terminal's normal Secure Keyboard
Entry setting. Do not disable security settings blindly to make the tool work.

The program waits up to three seconds after its own hidden-code or Keychain
interaction for Secure Input to clear naturally. It does not call an API to
disable that protection. If it remains active, the guard refuses to start.
If it appears during a run, the guard exits with status 3 and input is released.
For `lock`, the supervisor then attempts native macOS locking by default.
`--no-lock-on-failure` disables that recovery.

## The code does not unlock

- Use the physical keyboard, the supported layout and lowercase letters/top-row
  digits. Turn off Shift and Caps Lock. Remote or remapped events may not match
  the hardware/system event metadata expected by the detector.
- Type the complete code with no gap longer than 10 seconds. Release the last
  key; no Enter is needed. Other keys or modifier changes reset partial entry.
- A saved-code change affects the next run, not an already active guard.
- Version 0.2.0 refuses a second blocking instance. Older versions and other
  input blockers do not share its reservation and can still interfere.

A timed run expires. For an unlimited run, terminate the printed PID from a
session controllable from another device, such as SSH: `kill -TERM <PID>`. Ctrl-C on the blocked
keyboard will not reach the process. A default `lock` requests native macOS
locking on termination; use the printed supervisor PID for recovery.

## Overlay or native-lock fallback

Since 0.3.0, `lock` is supervised by default; release 0.2.0 needs
explicit `--lock-on-failure`. Privacy always needs `--privacy`, which uses a
native material; Reduce transparency makes it opaque, and some text may remain
readable even with transparency enabled. Whole-display capture may see the
overlay. Test your actual agent capture path with a bounded trial.

Failure recovery requires Accessibility access and the validated English
Finder Lock Screen menu action. If unavailable, default `lock` refuses to start.
`probe` checks availability without locking; run it in the same launch context.
`--no-lock-on-failure` opts out and accepts failure releasing input without
a macOS password prompt. An accepted request is not proof of locking.
If a Codex curtain appears after fallback, the guard's filter has been removed:
try a physical key or click, then authenticate normally. See the detailed
[limits and recovery tests](privacy-and-recovery.md).

## Keychain prompts or errors

The item is a generic password in the user's default file-based Keychain:

| Attribute | Value |
| --- | --- |
| Service | `local.workstation.input-guard` |
| Account | `unlock-code` |
| Label | `Input Guard unlock code` |

It uses the Keychain's normal access controls and is not configured for iCloud
sync. The executable is ad-hoc signed; changing its code or rebuilding can
cause macOS to ask for access again. Complete a legitimate native prompt
yourself. Never add broad trusted-application rules or disable prompts to
work around denial. A denied/cancelled/locked-Keychain error leaves input
unblocked. Only a missing item permits a temporary-code prompt.

`set-code` updates an existing value in place; `forget-code` removes only the
matching item in that default Keychain. Changing the default Keychain can make
an item in another Keychain unavailable to the tool. Deleting the binary alone
does not delete the saved code.

## The agent stops working

If its events pass through the session tap, the guard will block them too. The
program does not classify every synthetic event as safe. Another agent's
physical-input detection may also pause its session independently of this tap.

Use the short [compatibility procedure](compatibility.md), report the specific
agent/backend and versions, and do not rely on this guard for that setup until
it passes. Changing the session or switching to DOM automation does not prove
the original native session remained compatible.

## Build and installation

The build requires macOS and Apple's Command Line Tools or Xcode. A warning
about `SecKeychainCopyDefault` deprecation is expected: this standalone CLI
uses the file-based default Keychain rather than an entitlement-dependent app
Keychain. This path should be rechecked on future macOS releases.

For build automation, `INPUT_GUARD_BUILD_DIR` selects a build directory and
`INPUT_GUARD_ARCH` selects `x86_64` or `arm64`. `INPUT_GUARD_INSTALL_DIR` selects
an installation directory instead of `~/.local/bin`. These are filesystem/build
options, not ways to supply a code. Cross-compilation does not prove input
handling on that architecture.

## Exit status

| Status | Meaning |
| --- | --- |
| `0` | Normal completion, expiry, accepted unlock code or successful management command. |
| `1` | Permission, Keychain, layout preflight or event-tap setup failure. |
| `2` | Invalid command/duration/code input, unsupported layout or missing interactive input for code entry. |
| `3` | Runtime protection lost or supervised worker failure. Input is released; supervised mode attempts native locking. |

Unsupervised signal termination has the usual shell-specific signal status.
Timed runs have a SIGALRM backstop in addition to the run-loop deadline. Cleanup
has its own short backstop; unlimited runs have no duration limit. Supervised
mode also monitors the event-loop heartbeat and handles detected failure with
teardown followed by a best-effort native-lock request.

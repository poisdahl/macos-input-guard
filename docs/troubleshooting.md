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
If it appears during `lock`, the guard requests the normal macOS lock screen
and retains remaining filtering. That request can fail; see [the security
model](../SECURITY.md). `trial` and `observe` still exit on protection loss.

## The code does not unlock

- Use the physical keyboard, the supported layout and lowercase letters/top-row
  digits. Turn off Shift and Caps Lock. Remote or remapped events may not match
  the hardware/system event metadata expected by the detector.
- Type the complete code with no gap longer than 10 seconds. Release all held
  keys and mouse buttons; no Enter is needed. Other keys or modifier changes
  reset partial entry. An incorrect complete entry is cleared automatically.
- After five incorrect complete entries, wait 30 seconds before retrying.
  Modifier keys and partial-entry resets do not bypass this cooldown.
- If key/button releases were missed during Secure Input or tap loss, the guard
  may conservatively remember an input as held. Pressing and releasing that
  key/button can clear it; otherwise use timed expiry or the explicit recovery
  command below. A hardware-state snapshot is not treated as permission to
  leak queued release events into the foreground application.
- A saved-code change affects the next run, not an already active guard.
- A second blocking instance is refused. Older versions do not participate in
  this advisory lock; stop them before testing or updating.

A timed run expires. For an unlimited run, terminate the printed PID from a
separate terminal or SSH session: `kill -TERM <PID>` requests macOS Lock Screen
and retains remaining filtering. After normal macOS login, type the guard code
and end this run. Emergency `kill -KILL <PID>` removes it **without locking**.
Ctrl-C on the blocked keyboard will not reach the process.

## Lock Screen fallback unavailable

Run `input-guard check-lock`; this only checks menu availability. The fallback
currently requires the running system Finder, an English macOS interface and
the default Control-Command-Q Lock Screen menu shortcut. Other UI languages or
changed shortcuts are refused rather than guessing another menu action.

When ready to interrupt computer use, run `input-guard test-screen-lock` and
verify the real macOS login screen appears. An accepted AX action is not itself
proof of locking. After a fallback during `lock`, remaining filtering stays in
place; log in normally, enter the guard code, and start a fresh guard if needed.

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
| `3` | Protection loss occurred, or a screen-lock request was unavailable/rejected. See the messages; `lock` retains remaining filtering until code unlock or expiry. |

In `lock`, TERM/HUP/INT request the fallback while the event loop is responsive.
Uncaught signal termination has the usual shell-specific signal status. Timed runs also
have a default-action SIGALRM backstop two seconds after their duration, so a
stalled run loop cannot keep that timed process alive indefinitely. Unlimited
runs have no such expiry timer.

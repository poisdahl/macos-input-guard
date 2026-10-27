# Security model

The opt-in privacy/fallback options are described in
[privacy and recovery](docs/privacy-and-recovery.md). The supervisor attempts
native locking after an unexpected worker exit or detected failure, once its
worker has ended; it does not provide fail-closed security. A frosted
overlay is visual obscuration and does not guarantee unreadable screen content
or protection against capture.

Input Guard is intended to provide limited protection against casual
unauthorized keyboard and mouse use while compatible computer-use automation
continues. This includes deliberate attempts to use the Mac, not only
accidental interference. Supported input is blocked while the event tap is
enabled and receiving it.

This is a user-session input filter, not a macOS authentication boundary. The
session remains logged in; the optional overlay only obscures its contents. Bypass
resistance against a determined person with physical access has not been
established. Other processes running as the same user are not blocked. Use the
macOS lock screen when access must remain blocked if this process stops or
loses input interception.

The guard operates at a Core Graphics session event tap and requests all event
types available there. It swallows captured events, including synthetic events.
Version 0.1.2 blocked Mission Control swipes in a supervised Intel Mac test;
events handled elsewhere can still bypass it. Media keys, system shortcuts and
multitouch gestures are not comprehensively covered. Hardware/system source metadata used
by the code detector is not a cryptographic proof of origin.

## Failure behavior

- Without `--lock-on-failure`, a disabled tap, Secure Input or a changed layout
  causes the guard to stop.
  This intentionally **fails open**: local input becomes available again.
  This default mode does not invoke the macOS lock screen or require a macOS password
  when that happens. Failure can therefore expose the still-unlocked desktop
  without any reboot or knowledge of the guard's code.
- With `--lock-on-failure`, unexpected worker termination or a detected failure
  triggers teardown followed by one best-effort macOS-lock request. Terminating
  the supervisor also requests locking when recovery is possible. Accepted code
  unlock and timed expiry release input without locking. See the detailed limits
  in [privacy and recovery](docs/privacy-and-recovery.md).
- Process termination, logout or restart removes the input filter. There is no daemon
  or automatic restart.
- `lock` is unlimited by default. Timed runs have both a run-loop deadline and
  a SIGALRM backstop; unlimited runs have neither duration limit.
- Only one blocking instance should run at a time. Version 0.2.0 enforces this
  with a per-user instance reservation; older versions do not participate.
- The guard does not prevent sleep or preserve an agent session across OS
  locking, logout, restart or a permission change.

## Restart and normal macOS protection

Restarting ends the running guard and computer-use session. With automatic
login disabled, normal macOS startup presents the login window; restarting is
not, by itself, a way to resume the unlocked account. Apple documents that
[FileVault requires manual login and disables automatic login](https://support.apple.com/en-us/102316).
If automatic login is enabled, that assumption does not hold. Input Guard does
not inspect or change these settings.

Authentication after restart is provided by macOS independently of this tool.
It does not address failures in the existing logged-in session. Sleep and
display-off password requirements are also separate macOS settings.

## Codes and diagnostics

Codes contain 8–64 lowercase ASCII letters/digits. Temporary codes and the
partial unlock buffer exist in process memory; the application does not print
them or write them to a configuration file. Saved codes use an exact generic
password item in the default local file-based macOS Keychain with its normal
access controls. Keychain data is retrieved before blocking begins.

The code is not an OS credential and should not reuse a login password. This
project does not claim hardened secret-memory erasure, resistance to a local
debugger, brute-force protection or protection from other processes running as
the same user. The Keychain is used for storage, not to elevate the guard into
an authentication mechanism.

`observe` reports counts, event types, source PIDs and executable paths. It does
not output typed text, keycodes, clipboard contents or pointer coordinates.
Paths may contain a username or application names. Review diagnostics and
screenshots before sharing them. Never include unlock codes or Keychain exports
in an issue.

## Reporting a problem

Report ordinary bugs through GitHub Issues with non-sensitive reproduction
steps. For security-sensitive details, use
[GitHub private vulnerability reporting](https://github.com/poisdahl/macos-input-guard/security/advisories/new).
Please distinguish a new defect from the intentionally limited security model
above. There is no promised security-response service level.

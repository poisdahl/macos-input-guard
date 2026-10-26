# Security model

Input Guard is a local input-interference tool. It does not authenticate a
macOS login, hide screen contents, encrypt a desktop session, or establish a
boundary against someone with physical or same-user process access. Do not use
it as a substitute for the macOS lock screen when protecting confidential data.

The guard operates at a Core Graphics session event tap. It swallows ordinary
keyboard and pointer events seen there, including synthetic events. Events
handled elsewhere can bypass it. Media keys, system shortcuts and multitouch
gestures are not comprehensively covered. Hardware/system source metadata used
by the code detector is not a cryptographic proof of origin.

## Failure behavior

- A disabled tap, Secure Input or a changed layout causes the guard to stop.
  This intentionally **fails open**: local input becomes available again.
- Process termination, logout or restart removes the guard. There is no daemon
  or automatic restart.
- `lock` is unlimited by default. Timed runs have both a run-loop deadline and
  a SIGALRM backstop; unlimited runs have neither duration limit.
- Only one blocking instance should run at a time. There is no singleton lock.
- The guard does not prevent sleep or preserve an agent session across OS
  locking, logout, restart or a permission change.

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

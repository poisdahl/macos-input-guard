# Security model

Input Guard is intended to provide limited protection against casual
unauthorized keyboard and mouse use while compatible computer-use automation
continues. The supported controls are blocked while the guard is active; a
person who does not know the code cannot simply type or click through that
filter. This purpose includes deliberate attempts to use the Mac, not only
accidental interference.

This is a user-session input filter, not a macOS authentication boundary. The
session remains logged in and its screen contents remain visible. Bypass
resistance against a determined person with physical access has not been
established. It also provides no protection from other processes running as
the same user. Detected loss now requests the real macOS lock screen as a
best-effort fallback. Use the macOS lock screen directly when access must
remain blocked even if this process stops or loses input interception.

The guard operates at a Core Graphics session event tap. It swallows ordinary
keyboard and pointer events seen there, including synthetic events. Events
handled elsewhere can bypass it. Media keys, system shortcuts and multitouch
gestures are not comprehensively covered. Hardware/system source metadata used
by the code detector is not a cryptographic proof of origin.

## Failure behavior

- Detected tap loss, Secure Input, unsupported layout or lost Accessibility trust
  causes `lock` to attempt tap recovery and request the normal macOS Lock Screen
  action through Accessibility. TERM/HUP/INT request the same fallback. This can
  interrupt computer use, intentionally prioritizing protection on detected loss.
- The fallback targets only the system Finder's Apple-menu item named **Lock
  Screen**, with its default Control-Command-Q shortcut. It requires an English
  macOS interface. Missing/ambiguous targets refuse startup; no alternative menu
  command or synthesized shortcut is used.
- The request runs off the event-tap thread with bounded AX messaging and a
  lookup deadline. **Accepted means an action request was accepted, not proof
  of lock state.** Remaining filtering stays active after accepted or failed
  requests. A failed request can retry after 15 seconds while loss persists.
  Explicit TERM/HUP/INT can retry when no request is pending.
- After an accepted request, automatic lock requests are suppressed for that
  run to avoid repeatedly locking the user during login. Enter the guard code
  after logging back in to end this guard, then start a fresh run before relying
  on automatic fallback again. A stalled fallback cannot indefinitely delay a
  completed owner code unlock; the event loop releases that deferral after five
  seconds if it remains responsive.
- This is **not guaranteed fail-closed protection**. An interception gap may
  precede detection; Secure Input deliberately withholds keyboard events; AX
  permission loss may also prevent the fallback. Crashes, SIGKILL, suspension
  and a stalled event loop are not covered by these in-process checks. No
  independent watchdog or OS-level security boundary is installed.
- Correct code entry and explicit timed expiry intentionally remove the filter
  without requesting macOS locking. Timed runs retain a default-action SIGALRM
  backstop two seconds after their deadline, including during a pending lock
  request. Unlimited mode has no expiry.
- One blocking process per user is enforced through an OS-held advisory lock.
  Process death releases that lock; observation does not acquire it.
- The guard does not prevent sleep, hide the display, or preserve an agent
  session across macOS locking, logout, restart or a permission change.

The earlier 0.1.0 release immediately removed its filter on detected loss.
The changes above reduce avoidable failure paths but do not eliminate the
underlying limitations. See the [audit notes](docs/security-audit.md).

## Restart and normal macOS protection

Restarting ends the running guard and the computer-use session. With automatic
login disabled, normal macOS startup presents the login window; restarting is
not, by itself, a way to resume the unlocked account. Apple documents that
[FileVault requires manual login and disables automatic login](https://support.apple.com/en-us/102316).
If automatic login is enabled, that assumption does not hold. Input Guard does
not inspect or change these settings.

Authentication after restart is provided by macOS, independently of this tool.
It does not eliminate the interception gaps or process-failure paths in the
existing logged-in session.
Sleep and display-off password requirements are also separate macOS settings;
see [Apple's wake-password instructions](https://support.apple.com/guide/mac-help/require-a-password-after-waking-your-mac-mchlp2270/mac).

## Codes and diagnostics

Codes contain 8–64 lowercase ASCII letters/digits. Temporary codes and the
partial unlock buffer exist in process memory; the application does not print
them or write them to a configuration file. Saved codes use an exact generic
password item in the default local file-based macOS Keychain with its normal
access controls. Keychain data is retrieved before blocking begins.

The code is not an OS credential and should not reuse a login password. This
project does not claim hardened secret-memory erasure, resistance to a local
debugger or protection from other processes running as the same user. Five
incorrect complete code entries trigger a 30-second cooldown that keeps input
blocked; this throttles guesses but is not hardened brute-force resistance. The Keychain is used for storage, not to elevate the guard into
an authentication mechanism.

`observe` reports counts, event types, source PIDs and executable paths. It does
not output typed text, keycodes, clipboard contents or pointer coordinates.
Detailed diagnostic counters are capped at 256 event-type/source pairs;
`lock` mode retains only a scalar event count. Status output is bounded,
best effort and may be dropped under backpressure. Paths may contain a username
or application names. Review diagnostics and
screenshots before sharing them. Never include unlock codes or Keychain exports
in an issue.

## Reporting a problem

Report ordinary bugs through GitHub Issues with non-sensitive reproduction
steps. For security-sensitive details, use
[GitHub private vulnerability reporting](https://github.com/poisdahl/macos-input-guard/security/advisories/new).
Please distinguish a new defect from the intentionally limited security model
above. There is no promised security-response service level.

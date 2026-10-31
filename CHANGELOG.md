# Changelog

## 0.3.1 — 2026-10-31

Preserve bounded editing history so Backspace can correct unlock input that
exceeds the code length. Add non-interactive code-entry regression tests.
Prepare privacy overlays before creating the event tap and bound temporary
AppKit allocations during callbacks. Report the stop reason before count dumps.

Accept queued, current heartbeats after supervisor scheduling delays, preserve
pre-arm worker exit statuses, and restore terminal settings after pre-arm
termination. Give native-lock discovery a bounded retry budget and longer
Accessibility call timeout while still pressing at most once; report ambiguous
press responses as unconfirmed. Add fake-worker and injected recovery tests.
Owner-supervised checks on Intel/macOS 15.8.1 passed physical input blocking,
timed expiry, corrected saved-code unlock and separate crash/hang recovery.
See the [qualification evidence](docs/privacy-and-recovery.md#review-fix-candidate--2026-10-31).

## 0.3.0 — 2026-10-28

Make failure recovery the default for `lock`, with explicit
`--no-lock-on-failure` opt-out. Keep `trial` unsupervised and privacy opt-in.
Check native-lock availability before arming, and expose it through `probe`.
Repair orphan-worker recovery for controlled local/setup failures and recheck
active guards immediately before installation.

Allow unmodified display/keyboard brightness up/down events, with tracked
press/release pairing and modifier-shortcut rejection.

Document bounded Claude Desktop Code/Background compatibility tests, native
lock comparisons, and the general input-guard use case. Privacy remains opt-in.

## 0.2.0 — 2026-10-27

Add opt-in native screen frosting and unlock instructions (`--privacy`), an
overlay-only `preview`, and a temporary failure supervisor (`--lock-on-failure`).
The supervisor ends the input-filter worker before requesting the macOS lock,
so physical input can dismiss a Codex curtain and reach login. Normal code
unlock and timed expiry do not request locking. Default commands remain
unsupervised and show no overlay.

Enforce a per-user blocking-instance reservation and keep stalled terminal
output from blocking the event loop. Add non-interactive fault-injection tests.
On one Intel/macOS 15.8.1 setup, supervised tests covered the combined overlay,
physical input blocking, existing native Codex continuity, saved-code unlock,
worker crash/hang recovery and physical takeover after a Codex curtain.

Screen frosting is not guaranteed to hide readable text. Native locking remains
best effort, requires the validated English Finder Lock Screen action, and is
not fail-closed protection. See [limits and evidence](docs/privacy-and-recovery.md).

## 0.1.2 — 2026-10-26

Request all event types available at the session tap, including gesture events
omitted by the earlier explicit list. A supervised Intel test blocked Mission
Control swipes while the same native Codex session continued. Verify ordinary
event-mask registration at startup and report the actual registered mask.

Other gestures and input paths still require their own qualification. Failure
behavior is unchanged; the experimental screen-lock fallback is not included.

## 0.1.1 — 2026-10-26

Remove periodic `ACTIVE` output from ordinary timed and unlimited locks.
Keep progress output in `trial` and preserve startup/failure/exit messages.
Input filtering, code unlock and failure behavior are unchanged from 0.1.0.
The experimental screen-lock fallback is not included in this release.

## 0.1.0 — 2026-10-26

Initial public source release: session input filtering, typed-code unlock,
optional local Keychain storage, unlimited-by-default locks, bounded trials,
passive diagnostics and native build/install scripts.

Includes English setup, recovery, security and compatibility documentation,
non-interactive CLI checks, and Intel/Apple Silicon build CI. Manual
computer-use compatibility is limited to the documented Intel/native Codex
test; Claude Code and other routes remain untested.

# Changelog

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

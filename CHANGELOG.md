# Changelog

## 0.2.0 — unreleased

Security audit hardening for limited protection against unauthorized physical
use: bounded nonfatal logging, complete-attempt cooldown, held-input release,
single blocking instance, actual requested event-mask verification and bounded
diagnostic state. Detected protection loss and termination signals now attempt
the native macOS Lock Screen action while retaining remaining filtering.

The fallback is best effort and currently requires the system Finder's English
Lock Screen menu with its default shortcut. Crashes/SIGKILL and interception
gaps remain outside its guarantees. New isolated security regressions run in CI;
manual validation of the changed runtime is still required.

## 0.1.0 — 2026-10-26

Initial public source release: session input filtering, typed-code unlock,
optional local Keychain storage, unlimited-by-default locks, bounded trials,
passive diagnostics and native build/install scripts.

Includes English setup, recovery, security and compatibility documentation,
non-interactive CLI checks, and Intel/Apple Silicon build CI. Manual
computer-use compatibility is limited to the documented Intel/native Codex
test; Claude Code and other routes remain untested.

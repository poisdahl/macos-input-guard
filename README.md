# Input Guard for macOS

[![Build and smoke tests](https://github.com/poisdahl/macos-input-guard/actions/workflows/ci.yml/badge.svg)](https://github.com/poisdahl/macos-input-guard/actions/workflows/ci.yml)
[MIT licensed](LICENSE)

A command-line tool that blocks local keyboard and mouse input while compatible
computer-use automation continues. Unlock by typing a code, or use a timer.

**Limited protection against casual unauthorized use:** the desktop stays
unlocked. By default, `lock` attempts the macOS lock screen after a failure;
normal code unlock and timed expiry release input normally. Screen frosting is
optional. Recovery is best effort, not a guarantee that macOS is locked.
Use the macOS lock screen when
you need stronger physical-access protection. Read the [security model](SECURITY.md).

## Why it exists

Input Guard was built to add a local input barrier to an **already-running
computer-use session**, without logging out, switching desktops or restarting
the agent.

OpenAI also offers [Locked use](https://learn.chatgpt.com/docs/computer-use#locked-use)
for automation after macOS locks. Its documented workflow starts a task from a
connected device after locking; it does not say that all previously started
sessions are unsupported. Input Guard instead filters input while leaving the
desktop unlocked, providing weaker protection than macOS locking.

## Compatibility

- **Tested:** an existing native Codex session kept using Calculator while local
  typing, pointer input and Mission Control swipes were blocked on an Intel Mac.
- **Not runtime-tested:** Apple Silicon, Claude Code-based setups, Jump Desktop
  and other agents or remote-desktop tools. CI checks builds and CLI behavior on
  Intel and Apple Silicon, not physical input handling.
- Captured events are dropped, **including synthetic input**, except the four
  display/keyboard brightness controls described below.
  Compatibility depends on the input backend; not every gesture or input path
  is covered. Verify your setup with the short trial below.

See [compatibility and manual verification](docs/compatibility.md) for evidence
and the full test procedure.

The local development build allows display-brightness up/down and keyboard-
backlight up/down events while blocking. Use the lighting buttons without
modifiers; Fn is allowed when needed. Ordinary F-keys and modifier shortcuts
such as Option-brightness remain blocked. Release modifier keys before starting
the guard: a modifier held during activation can keep lighting controls blocked
for that run. This change is not in release 0.2.0; it has passed bounded physical
trials on one Intel Mac. Verify it on your own keyboard before relying on it.

## Install

Requires **macOS 13+**, Apple Command Line Tools/Xcode with **Swift 5.7+**, and
Accessibility permission. Code unlock supports Apple **US, ABC, Norwegian and
Norwegian Extended QWERTY** layouts; other layouts are rejected.

```sh
xcode-select --install    # If Apple's developer tools are not installed
git clone https://github.com/poisdahl/macos-input-guard.git
cd macos-input-guard
./scripts/install.sh
```

Installs a native, locally ad-hoc-signed build at `~/.local/bin/input-guard`.
There is no notarized binary download, service or autostart. Add `~/.local/bin`
to your `PATH`, or use the full executable path below; installation does not
change your shell configuration.

## Quick start

**Run only one blocking instance at a time.** Start your agent in a harmless app
such as Calculator, then run:

```sh
~/.local/bin/input-guard trial 15
```

The trial blocks input for 15 seconds and releases it automatically. During that
window, try the physical controls and confirm the **same existing agent session**
still works. If needed, grant the executable or launching application permission
under **System Settings → Privacy & Security → Accessibility**, then retry.

Next, test code unlock with a timed run:

```sh
input-guard lock 60       # Automatically releases after 60 seconds
```

Without a saved code, hidden prompts ask for a temporary code: **8–64 lowercase
letters/digits (`a-z`, `0-9`)**. Do not reuse your macOS password.

**Unlock:** type the code anywhere on the physical keyboard with Shift and Caps
Lock off, then release the final key. **No Enter.** Backspace corrects entry;
other keys, modifiers or a gap over 10 seconds reset it.

Only after both tests succeed, with recovery access from another device (such
as a working SSH session):

```sh
input-guard lock          # Unlimited by default; no periodic ACTIVE output
```

To save or replace a reusable code in the local macOS Keychain:

```sh
input-guard set-code      # Future locks use the saved code automatically
```

Remove it with `input-guard forget-code`. Changes affect future runs. Rebuilds
may trigger Keychain approval again; keep its access controls intact. Codes
are never accepted through arguments or pipes.

Test the saved code with `input-guard lock 60` before an unlimited run.

Use `input-guard --help` for all commands and duration limits, `probe` for
permission/layout diagnostics, and `observe 15` for passive event counts.

## Recovery and limits

`lock` starts a temporary supervisor by default. It removes the input filter
before attempting the macOS lock after a fault. Normal code unlock and timed
expiry do not request locking. **Terminating the guard requests macOS locking.**
Use the printed supervisor PID when terminating it from another session.

Screen frosting is optional:

```sh
input-guard preview 20            # Overlay only; input remains usable
input-guard lock 60 --privacy     # Supervised lock plus overlay
```

The fallback requires Accessibility access and Finder's English **Lock Screen**
action. If unavailable, the guard refuses to start; it never silently disables
failure locking. `input-guard probe` checks availability in the current launch
context. Frosting does not guarantee unreadable text or compatibility with every
capture backend. See [limits and test results](docs/privacy-and-recovery.md).

`trial` has no failure locking unless `--lock-on-failure` is explicit. To opt out
for a regular lock, use `--no-lock-on-failure`: failures then release input
**without macOS authentication**. Ctrl-C on the blocked keyboard is blocked too;
keep a way to terminate the printed PID from another device, such as SSH.

The guard does not prevent sleep, logout or restart, or preserve automation
across them. Restart/login protection depends on your macOS settings.

For code-entry, permissions or Keychain problems, see [troubleshooting](docs/troubleshooting.md).
Before extended unattended use, read the [security model](SECURITY.md).

## Help, development and removal

Report bugs through [Issues](https://github.com/poisdahl/macos-input-guard/issues);
use [private vulnerability reporting](https://github.com/poisdahl/macos-input-guard/security/advisories/new)
for security-sensitive reports. Never share codes; diagnostic paths can contain
usernames. See [Contributing](CONTRIBUTING.md) for build/test commands and report
requirements. Maintained by [@poisdahl](https://github.com/poisdahl).

Stop the guard before updating or uninstalling. To uninstall, optionally run
`input-guard forget-code`, delete `~/.local/bin/input-guard`, and remove its
unneeded Accessibility grant. Deleting the executable alone keeps the saved code.

## License and credit

[MIT](LICENSE). The session event-tap foundation is adapted from
[mac-inputlock](https://github.com/choiyounggi/mac-inputlock) by Younggi Choi;
its copyright and license are retained in [third-party notices](THIRD_PARTY_NOTICES.md).
Independent project; not affiliated with OpenAI, Anthropic or Apple.

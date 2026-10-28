# Input Guard for macOS

[![Build and smoke tests](https://github.com/poisdahl/macos-input-guard/actions/workflows/ci.yml/badge.svg)](https://github.com/poisdahl/macos-input-guard/actions/workflows/ci.yml)
[MIT licensed](LICENSE)

Block captured local keyboard, pointer and trackpad input while applications
keep running. Release input with a code or timer; optional screen frosting
obscures the desktop and shows unlock instructions.

Use it against accidental input or casual unauthorized use. **macOS stays logged
in and unlocked.** Protection is weaker than the macOS lock screen and does not
replace authentication. See the [security model](SECURITY.md).

## Computer use, including Claude

A macOS lock can stop desktop automation. Input Guard lets compatible automation
continue in the existing session while filtering local input.

**Tested with Claude Desktop 4.29.0, Code tab, Background mode, Haiku 5.5 Low**
on one Intel Mac running macOS 15.8.1. The same existing session operated
Calculator and captured clear results while local typing, pointer/clicks and
Mission Control swipes were blocked, including with `--privacy`. A separate
native-macOS-lock test blocked Claude's clicks.

Our native Codex Calculator tests also passed, but native macOS locking worked
in separate tests, making Input Guard potentially unnecessary for that setup.
Other Claude modes, the CLI, agents, remote desktop and Apple Silicon require
their own trial. Captured synthetic input is blocked; there is no trusted-agent
allowlist. See [compatibility and test evidence](docs/compatibility.md).

## Install

Requires **macOS 13+**, Apple Command Line Tools or Xcode with **Swift 5.7+**,
and Accessibility permission. Code unlock supports Apple's **US, ABC, Norwegian
and Norwegian Extended QWERTY** layouts.

```sh
xcode-select --install    # If Apple's developer tools are missing
git clone https://github.com/poisdahl/macos-input-guard.git
cd macos-input-guard
./scripts/install.sh
```

Installs a native, ad-hoc-signed executable at `~/.local/bin/input-guard`, with no
service or autostart. Add `~/.local/bin` to your `PATH` or use the full path;
installation does not change permissions or shell configuration.

## Start with a timed trial

Run one blocking instance at a time. **Release all keys and buttons before
starting.** For computer use, first start the actual agent session in a harmless
app such as Calculator, then run:

```sh
~/.local/bin/input-guard trial 30 --privacy
```

Try physical typing, clicks and gestures. Confirm the **same agent session**
still works and input returns at expiry. If permission is missing, enable the
intended executable or launching app under **System Settings → Privacy &
Security → Accessibility**, then retry. Permissions can differ by launch context.

Next, test code unlock with a one-minute limit:

```sh
~/.local/bin/input-guard lock 60
```

Without a saved code, hidden prompts ask for a temporary code: **8–64 lowercase
letters/digits (`a-z`, `0-9`)**. Codes are never accepted through arguments or
pipes. Do not reuse your macOS password or share your code.

**To unlock:** type the code on the physical keyboard with Shift and Caps Lock
off, then release the final key. **No Enter.** Backspace corrects entry; other
keys, modifiers or a gap over 10 seconds reset partial entry.

```sh
input-guard set-code       # Save or replace a code in the local macOS Keychain
input-guard lock           # Unlimited; use only after timed/code-unlock tests
input-guard lock --privacy # Unlimited with optional screen frosting
```

Keep recovery access from another device, such as SSH, for unlimited use.
`forget-code` removes the saved code; changes affect future runs. Retest after
saving/changing a code. Rebuilds may prompt for Keychain access again; preserve
its normal access controls.

## Controls and recovery

| Command or option | Behavior |
| --- | --- |
| `lock [seconds]` | Unlimited by default; timed runs up to 8 hours. Failure recovery enabled. |
| `trial [seconds]` | Code-free trial, 1–60 seconds (default 30); no failure recovery by default. |
| `--privacy` | Optional screen frosting for `lock` or `trial`. |
| `--lock-on-failure` | Explicitly enables recovery, including for `trial`. |
| `--no-lock-on-failure` | Opts out: faults release input without macOS authentication. |
| `preview 20` | Overlay only; input remains usable. |

Unmodified display brightness and keyboard backlight up/down remain available;
Fn is allowed. Modifier shortcuts stay blocked. Release modifiers before arming:
a held modifier can keep lighting blocked for that run. Other gestures, shortcuts
and device-specific input paths are not comprehensively covered.

After a fault, a temporary supervisor removes the filter/overlay before attempting
the macOS lock. **Terminating a supervised guard requests locking; normal code
unlock and timed expiry do not.** For emergency termination from another session,
use `kill -TERM <printed-supervisor-PID>`. Ctrl-C on the blocked keyboard is blocked too.

Recovery requires Accessibility and the system Finder's English **Lock Screen**
action; supervised startup refuses if unavailable. Recovery is **best effort**:
there is an exposure gap, requests can fail, and acceptance does not prove macOS
is locked. A fallback lock can interrupt computer use. Sleep, logout and restart
can also end automation.

Frosting does not guarantee unreadable content or prevent capture; whole-display
screenshots may include it. See [privacy and recovery](docs/privacy-and-recovery.md).

## Help and removal

Run `input-guard --help` for commands, `probe` for diagnostics, or `observe 15`
for passive event counts. See [troubleshooting](docs/troubleshooting.md),
[Contributing](CONTRIBUTING.md) and [Issues](https://github.com/poisdahl/macos-input-guard/issues).
Report vulnerabilities [privately](https://github.com/poisdahl/macos-input-guard/security/advisories/new);
remove personal information from diagnostics before sharing.

Stop the guard before updating or uninstalling. To uninstall, optionally run
`input-guard forget-code`, delete `~/.local/bin/input-guard`, and remove its
unneeded Accessibility grant. Deleting the executable alone retains the saved code.

## License and credit

[MIT](LICENSE). Adapted from Younggi Choi's
[mac-inputlock](https://github.com/choiyounggi/mac-inputlock); see
[third-party notices](THIRD_PARTY_NOTICES.md) for the adapted portions and retained license.
Independent project; not affiliated with OpenAI, Anthropic or Apple.

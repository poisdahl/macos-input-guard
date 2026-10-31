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

Tested and working with **Claude Desktop 4.29.0**.

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

## Use

Run one blocking instance at a time. **Release all keys and buttons before
starting.** For computer use, start the agent session first, then run:

```sh
~/.local/bin/input-guard lock
```

The default lock has no time limit. Type the unlock code to release input.
If permission is missing, enable the intended executable or launching app under
**System Settings → Privacy & Security → Accessibility**, then retry.
Permissions can differ by launch context.

Without a saved code, hidden prompts ask for a temporary code: **8–64 lowercase
letters/digits (`a-z`, `0-9`)**. Codes are never accepted through arguments or
pipes. Do not reuse your macOS password or share your code.

**To unlock:** type the code on the physical keyboard with Shift and Caps Lock
off, then release the final key. **No Enter.** Backspace corrects entry; other
keys, modifiers or a gap over 10 seconds reset partial entry.

```sh
input-guard set-code       # Save or replace a code in the local macOS Keychain
input-guard lock 3600      # Release automatically after one hour
input-guard lock --privacy # Unlimited with optional screen frosting
```

Keep recovery access from another device, such as SSH, for unlimited use.
`forget-code` removes the saved code; changes affect future runs. Rebuilds may
prompt for Keychain access again; preserve its normal access controls.

## Controls and recovery

| Command or option | Behavior |
| --- | --- |
| `lock [seconds]` | Unlimited by default; timed runs up to 8 hours. Failure recovery enabled. |
| `--privacy` | Optional screen frosting while input is blocked. |
| `--lock-on-failure` | Explicitly enables failure recovery, already the default for `lock`. |
| `--no-lock-on-failure` | Opts out: faults release input without macOS authentication. |
| `preview 20` | Overlay only; input remains usable. |

Unmodified display brightness and keyboard backlight up/down remain available;
Fn is allowed. Turn Caps Lock off. Modifier shortcuts stay blocked.
Release modifiers before arming:
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

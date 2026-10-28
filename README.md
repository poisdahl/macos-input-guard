# Input Guard for macOS

[![Build and smoke tests](https://github.com/poisdahl/macos-input-guard/actions/workflows/ci.yml/badge.svg)](https://github.com/poisdahl/macos-input-guard/actions/workflows/ci.yml)
[MIT licensed](LICENSE)

Block local keyboard and mouse input while an **already-running, compatible
computer-use session** continues. Release input by typing a code or letting a
timer expire, without restarting the agent or switching desktops.

The desktop remains logged in and unlocked. This provides limited protection
against casual unauthorized use; it is weaker than the macOS lock screen.
Read the [security model](SECURITY.md) before relying on it.

**Development build:** this README describes unreleased
`0.2.0+failure-default-dev`. Release 0.2.0 requires explicit `--lock-on-failure`
and has no brightness passthrough. The lock examples work with both versions;
check yours with `input-guard --version`.

## Compatibility

- An existing native Codex Calculator session continued during physical-input
  tests on one Intel Mac running macOS 15.8.1. The new development build still
  needs physical qualification.
- Apple Silicon, Claude Code, Jump Desktop and other agent or remote-desktop
  setups have not been physically qualified. CI checks builds and CLI behavior.
- The filter drops captured events, **including synthetic input**, except the
  lighting controls below. There is no
  trusted-agent allowlist, and not every gesture or input path is covered.

The development build passes four lighting controls: display brightness up/down
and keyboard backlight up/down, with no modifiers except Fn. Ordinary F-keys and
modifier shortcuts remain blocked. Test your actual setup using the
[compatibility procedure](docs/compatibility.md).

## Install

Requires **macOS 13+**, Apple Command Line Tools or Xcode with **Swift 5.7+**,
and Accessibility permission. Code unlock supports Apple **US, ABC, Norwegian
and Norwegian Extended QWERTY** layouts.

```sh
xcode-select --install    # If Apple's developer tools are missing
git clone https://github.com/poisdahl/macos-input-guard.git
cd macos-input-guard
./scripts/install.sh
```

Installs a native, locally ad-hoc-signed executable at `~/.local/bin/input-guard`.
There is no background service or autostart. Installation changes neither
permissions nor shell configuration; add `~/.local/bin` to your `PATH` or use
the full path.

## First run

Run one blocking instance at a time. **Release all keys and buttons before
starting.** Keep the existing agent working in a harmless app such as Calculator:

```sh
~/.local/bin/input-guard trial 15
```

Try physical typing, clicks and gestures during the trial, and confirm that the
**same agent session** still works and input returns at expiry. If permission is
missing, enable the intended executable or launching app under **System Settings
→ Privacy & Security → Accessibility**, then retry.

Next, test code unlock with a one-minute limit:

```sh
~/.local/bin/input-guard lock 60 --lock-on-failure
```

Without a saved code, hidden prompts ask for a temporary code: **8–64 lowercase
letters/digits (`a-z`, `0-9`)**. Codes are never accepted through arguments or
pipes. Do not reuse your macOS password or share your code.

**To unlock:** type the code on the physical keyboard with Shift and Caps Lock
off, then release the final key. **No Enter.** Backspace corrects entry; other
keys, modifiers or a gap over 10 seconds reset partial entry.

Use `input-guard set-code` to save or replace a code in the local macOS Keychain;
`input-guard forget-code` removes it. Changes affect future runs. Rebuilds may prompt for
Keychain access again; preserve its normal access controls.

Only after timed and code-unlock tests succeed, with recovery access from
another device such as SSH, use `input-guard lock --lock-on-failure` for an
unlimited run. Retest after saving or changing a code.

## Defaults, privacy and recovery

In the development build:

| Command or option | Behavior |
| --- | --- |
| `lock [seconds]` | Unlimited by default; up to 8 hours when timed. Failure recovery is enabled. |
| `trial [seconds]` | Timed, code-free trial; no failure recovery unless `--lock-on-failure` is supplied. |
| `--privacy` | Adds optional screen frosting to `lock` or `trial`. |
| `--no-lock-on-failure` | Disables recovery: faults release input without macOS authentication. |

Failure recovery uses a temporary supervisor. After a fault, it removes the
filter and overlay before attempting native macOS locking. **Terminating a
supervised guard requests locking; normal code unlock and timed expiry do not.**
For emergency termination from another session, use the printed supervisor PID.
Ctrl-C on the blocked keyboard is blocked too.

Fallback requires Accessibility access and the system Finder's English **Lock
Screen** action. If unavailable, a supervised run refuses to start. Recovery is
**best effort**: there is an input gap, requests can fail, and acceptance does
not prove macOS is locked. Sleep, logout and restart can end automation.

Preview frosting with `input-guard preview 20`; add `--privacy` to a bounded
trial or lock to test it. Frosting does not guarantee unreadable content or
prevent capture; whole-display screenshots may include it. See
[privacy and recovery](docs/privacy-and-recovery.md) for limits and qualification.

## Help and removal

Use `input-guard --help` for commands, `probe` for launch-context diagnostics,
and `observe 15` for passive event counts. See [troubleshooting](docs/troubleshooting.md),
[Contributing](CONTRIBUTING.md) and [Issues](https://github.com/poisdahl/macos-input-guard/issues).
Report vulnerabilities [privately](https://github.com/poisdahl/macos-input-guard/security/advisories/new);
remove personal information from diagnostics before sharing.

Stop the guard before updating or uninstalling. To uninstall, optionally run
`input-guard forget-code`, delete `~/.local/bin/input-guard`, and remove its
unneeded Accessibility grant. Deleting the executable alone retains the saved code.

## License and credit

[MIT](LICENSE). The session event-tap foundation is adapted from Younggi Choi's
[mac-inputlock](https://github.com/choiyounggi/mac-inputlock). See the retained
copyright and license in [third-party notices](THIRD_PARTY_NOTICES.md) and [LICENSE](LICENSE).
Independent project; not affiliated with OpenAI, Anthropic or Apple.

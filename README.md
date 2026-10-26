# Input Guard for macOS

[![Build and smoke tests](https://github.com/poisdahl/macos-input-guard/actions/workflows/ci.yml/badge.svg)](https://github.com/poisdahl/macos-input-guard/actions/workflows/ci.yml)
[MIT licensed](LICENSE)

A small command-line input guard intended to deter casual unauthorized use of
a Mac's keyboard and mouse while leaving the desktop available to compatible
computer-use automation.

An **already-running native Codex computer-use session** continued during a
supervised test on an Intel Mac. The guard does not log out, switch users,
cover the screen or restart the agent session.

**Limited physical-access protection: the desktop stays unlocked and visible.**
While its event tap is enabled and receiving the supported events, the guard
blocks ordinary local typing and pointer input, providing a barrier to someone
trying to use those controls without the code. It does not hide screen contents
or provide the guarantees of the macOS lock screen. If the guard stops or loses
interception, input can become available again **without a macOS password
prompt**. See the [security model](SECURITY.md), including how restart protection
depends on macOS settings.

It drops **all events captured at its session event tap**, which can include
synthetic input. Compatibility depends on how an agent sends events.

Claude Code-based computer-use setups and other agents are **not yet tested**.
Do not infer compatibility from the agent's name. See the
[compatibility notes and test procedure](docs/compatibility.md).

## Requirements

- macOS 13 or later and Apple Command Line Tools/Xcode with Swift 5.7 or later.
- Accessibility permission for the executable or the application launching it.
- For code unlock: an Apple **US, ABC, Norwegian or Norwegian Extended QWERTY**
  keyboard layout. Other layouts are rejected by `lock`.

The build script targets the current architecture (`x86_64` or `arm64`).
Physical input blocking and native Codex continuity have been tested on Intel;
Apple Silicon has not received that manual test. CI checks compilation and
non-interactive CLI behavior on both architectures, not physical input handling.

## Install from source

Install Apple's tools first if needed:

```sh
xcode-select --install
```

Then clone and build:

```sh
git clone https://github.com/poisdahl/macos-input-guard.git
cd macos-input-guard
./scripts/install.sh
```

This installs `~/.local/bin/input-guard`, using a local ad-hoc signature. It
does not start the guard, request permissions during installation, add a login
item or modify your shell configuration. This release distributes source;
there is no Developer ID-signed or notarized binary download.

If `~/.local/bin` is not on your `PATH`, use the full path shown below or add it
to your own shell configuration.

## First run: use a short trial

Start your computer-use session first, with a harmless target such as Calculator.
Then run:

```sh
~/.local/bin/input-guard trial 15
```

The trial blocks ordinary input for 15 seconds, then releases it automatically.
While it is active, confirm both that physical input is blocked and that the
**same existing agent session** can still work. Check the result before the
trial expires. If permission is missing, grant the intended application under
**System Settings → Privacy & Security → Accessibility**, then retry.

Complete this test before relying on an unlimited run. Run only one blocking
instance at a time. Detailed steps are in [compatibility](docs/compatibility.md).

## Lock and unlock

```sh
input-guard lock 60       # Automatically releases after 60 seconds
input-guard lock          # Unlimited by default
input-guard lock unlimited
```

Ordinary timed and unlimited `lock` runs print no periodic `ACTIVE` lines.
Startup messages, failures and the exit summary remain visible. The bounded
`trial` mode still prints progress each second for compatibility testing.

With no saved code, `lock` asks you to choose and confirm a temporary code.
Use **8–64 lowercase letters and digits (`a-z`, `0-9`)**. Entry is hidden.
Use a separate code, not your macOS login password.

**To unlock, type the code anywhere on the physical keyboard, with Shift and
Caps Lock off, then release the final key. Do not press Enter.** The code is
consumed by the guard. Backspace corrects partial entry; other keys, modifiers
or a gap longer than 10 seconds reset it. Validate code unlock with a timed
run before using unlimited mode.

### Save a fixed code

```sh
input-guard set-code      # Choose and confirm a code in Terminal
input-guard lock          # Automatically uses the saved code
```

The saved code is stored in the local default macOS Keychain, not a plaintext
configuration file. It is read before the guard starts. Only a missing item
falls back to a temporary prompt; other Keychain errors stop the command.

Run `set-code` again to replace it, or `input-guard forget-code` to remove it.
Changes apply to future runs; an active guard keeps its current in-memory code.
macOS may request Keychain approval again after a rebuild. Do not weaken the
item's access controls to avoid that prompt.

## Commands

| Command | Behavior |
| --- | --- |
| `lock [seconds\|unlimited]` | Code unlock; no duration means unlimited; timed runs allow 1–28,800 seconds. |
| `set-code` | Save or replace the code, using hidden interactive prompts. |
| `forget-code` | Remove this tool's saved Keychain item. |
| `trial [seconds]` | Block without a code for 1–60 seconds; default 30. |
| `observe [seconds]` | Passively count event types and sources for 1–60 seconds; default 30. |
| `probe` | Show Accessibility trust, Secure Input state and keyboard layout. |
| `--help`, `--version` | Show usage or version. |

Temporary codes are not saved. No codes are accepted through arguments or pipes,
and the application does not print them. `observe` outputs source process paths,
which may contain local usernames; review diagnostic output before sharing it.

## Recovery and limits

- The guard prints its PID. From another terminal or SSH session, stop that
  exact process with `kill -TERM <PID>`. Process termination removes its tap.
  **Ctrl-C typed on the blocked keyboard is also blocked.**
- Secure Input, a changed keyboard layout, or a disabled event tap ends the
  guard. It **fails open**: input becomes available again.
- Media keys, some system shortcuts and multitouch gestures are not
  comprehensively intercepted. Restarting the Mac ends the process.
- There is no protection for screen contents and no guarantee against a
  determined person at the machine. Use the macOS lock screen for that need.
- The guard does not keep the Mac awake or override sleep, lid closure,
  logout or shutdown. Use your normal power settings as appropriate.

Read [the security model](SECURITY.md) and
[troubleshooting](docs/troubleshooting.md) before extended unattended use.

## Build, check and remove

```sh
./scripts/build.sh        # Builds .build/input-guard without installing
./tests/smoke.sh          # Never blocks input or accesses Keychain
```

CI runs these checks on Intel and Apple Silicon. A green build is not proof of
computer-use compatibility; that requires the manual test on your setup.

Stop a running guard before reinstalling. To uninstall, first run
`input-guard forget-code` if you also want to remove the saved code, then delete
`~/.local/bin/input-guard`. Deleting the executable alone retains its Keychain
item. Remove an unneeded Accessibility grant through System Settings.

## License and credit

MIT. The session event-tap foundation is adapted from
[mac-inputlock](https://github.com/choiyounggi/mac-inputlock) by Younggi Choi.
Its copyright and license are retained. See
[third-party notices](THIRD_PARTY_NOTICES.md) for the exact source and the scope
of the adaptation.

This is an independent project, not affiliated with OpenAI, Anthropic or Apple.

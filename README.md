# Input Guard for macOS

[![Build and smoke tests](https://github.com/poisdahl/macos-input-guard/actions/workflows/ci.yml/badge.svg)](https://github.com/poisdahl/macos-input-guard/actions/workflows/ci.yml)
[MIT licensed](LICENSE)

A small command-line input guard intended to deter casual unauthorized use of
a Mac's keyboard and mouse while leaving the desktop available to compatible
computer-use automation.

An **already-running native Codex computer-use session** continued during a
supervised **0.1.0** test on an Intel Mac. **Do not install the 0.2.0 candidate:
its retained-filter fallback failed a supervised test with active Locked use.** The guard does not log out, switch users,
cover the screen or restart the agent session.

**Limited physical-access protection: the desktop stays unlocked and visible.**
An owner-observed trackpad swipe appeared to open Mission Control during a
blocked trial. Multitouch system gestures are not covered by the ordinary
keyboard/mouse result; they can reveal other windows.

While its event tap is enabled and receiving the supported events, the guard
blocks ordinary local typing and pointer input, providing a barrier to someone
trying to use those controls without the code. It does not hide screen contents
or provide the guarantees of the macOS lock screen. Detected protection loss
triggers a best-effort request for the normal
macOS lock screen, even if that interrupts computer use. This is not an atomic
handover: failures, bypasses or process termination can still expose input
**without a password prompt**. See the [security model](SECURITY.md), including
how restart protection depends on macOS settings.

It drops **all events captured at its session event tap**, which can include
synthetic input. Compatibility depends on how an agent sends events.

Claude Code-based computer-use setups and other agents are **not yet tested**.
Do not infer compatibility from the agent's name. See the
[compatibility notes and test procedure](docs/compatibility.md).

## Requirements

- macOS 13 or later and Apple Command Line Tools/Xcode with Swift 5.7 or later.
- Accessibility permission for the executable or the application launching it.
- For the macOS-lock fallback: the system Finder running, an **English macOS
  interface**, and its default Control-Command-Q Lock Screen shortcut. Other
  languages or changed shortcuts currently cause `lock` to refuse startup.
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

## First run: verify the fallback, then use a short trial

Before starting a computer-use session, check and test the macOS-lock request:

```sh
~/.local/bin/input-guard check-lock         # Read-only check
~/.local/bin/input-guard test-screen-lock   # Requests the macOS lock screen
```

The second command can interrupt active work and computer use. Run it only when
ready, verify the real macOS login screen appears, then unlock normally. An
accepted Accessibility action alone is not proof that the screen locked.

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

Complete this test before relying on an unlimited run. A second blocking
instance is rejected before code prompts. Detailed steps are in [compatibility](docs/compatibility.md).

## Lock and unlock

```sh
input-guard lock 60       # Automatically releases after 60 seconds
input-guard lock          # Unlimited by default
input-guard lock unlimited
```

Healthy `lock` runs are quiet after the startup messages: no periodic `ACTIVE`
lines are printed, for either timed or unlimited locks. Faults, code-entry
cooldowns and the final exit reason are still reported. The short `trial` mode
prints progress each second for compatibility testing.

With no saved code, `lock` asks you to choose and confirm a temporary code.
Use **8–64 lowercase letters and digits (`a-z`, `0-9`)**. Entry is hidden.
Use a separate code, not your macOS login password.

**To unlock, type the code anywhere on the physical keyboard, with Shift and
Caps Lock off, then release all held keys and mouse buttons. Do not press
Enter.** The code is consumed by the guard. Backspace corrects partial entry;
other keys, modifiers or a gap longer than 10 seconds reset it. An incorrect
complete entry is cleared. After five incorrect complete entries, code entry
pauses for 30 seconds while input remains blocked. Choose a long, uncommon code. Validate code unlock with a timed
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
| `check-lock` | Read-only check for the system Finder Lock Screen menu action. |
| `test-screen-lock` | Request the real macOS lock screen; interrupts computer use. |
| `--help`, `--version` | Show usage or version. |

Temporary codes are not saved. No codes are accepted through arguments or pipes,
and the application does not print them. `observe` outputs source process paths,
which may contain local usernames; review diagnostic output before sharing it.

## Recovery and limits

- The guard prints its PID. From another terminal or SSH session,
  `kill -TERM <PID>` requests the normal macOS lock screen. TERM/HUP/INT do not
  simply remove a `lock` guard anymore. **Ctrl-C on the blocked keyboard is also
  blocked.** Code unlock and explicit timed expiry still release normally.
- Detected Secure Input, an unsupported layout, revoked Accessibility access or
  a disabled event tap triggers the best-effort lock request. Remaining filtering
  is retained even when the request is accepted. After logging back in, enter
  the guard's code to finish; start a fresh run before relying on it again.
- **A crash, SIGKILL or a stalled process can still remove or disable protection
  without locking macOS.** Emergency `kill -KILL <PID>` forcibly releases the
  filter without requesting a lock. There is no watchdog service.
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
./tests/smoke.sh          # CLI validation
./tests/security.sh       # Isolated regressions; no input tap, screen lock or Keychain access
```

CI runs these checks on Intel and Apple Silicon. A green build is not proof of
computer-use compatibility; that requires the manual test on your setup.

Stop a running guard before reinstalling. To uninstall, first run
`input-guard forget-code` if you also want to remove the saved code, then delete
`~/.local/bin/input-guard`. Deleting the executable alone retains its Keychain
item. Blocking modes also use one advisory-lock file in the macOS per-user
temporary directory; the OS releases the lock when the process exits. Remove an unneeded Accessibility grant through System Settings.

## License and credit

MIT. The session event-tap foundation is adapted from
[mac-inputlock](https://github.com/choiyounggi/mac-inputlock) by Younggi Choi.
Its copyright and license are retained. See
[third-party notices](THIRD_PARTY_NOTICES.md) for the exact source and the scope
of the adaptation.

This is an independent project, not affiliated with OpenAI, Anthropic or Apple.

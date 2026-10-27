# Contributing

Keep changes small and preserve the observable failure behavior. Build and run
the non-interactive checks before opening a pull request:

```sh
./scripts/build.sh
./tests/smoke.sh
```

The tests require Python 3.9+; the installed executable does not. Supervisor
tests use substitute workers and a fake lock callback, without blocking input
or locking macOS. For overlay/fallback changes, also follow the supervised
[qualification procedure](docs/privacy-and-recovery.md#qualification).

Do not add an unattended lock, Keychain mutation or permission prompt to CI.
Changes to event filtering, code entry or failure handling need a supervised
bounded test using [the compatibility procedure](docs/compatibility.md).

Compatibility reports should identify macOS version, architecture, keyboard
layout, agent version/backend, whether the same existing session continued,
and which physical inputs were tested. Do not post codes, usernames in local
paths, private screenshots, Keychain exports or other credentials.

Preserve upstream copyright/license notices for adapted code. Identify the
source and license of any new third-party code in the pull request.

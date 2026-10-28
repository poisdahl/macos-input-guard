#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
build_dir=${INPUT_GUARD_BUILD_DIR:-"$project_dir/.build"}
binary="$build_dir/input-guard"
test_output=$(mktemp -d "${TMPDIR:-/tmp}/input-guard-smoke.XXXXXX")
trap 'rm -rf "$test_output"' EXIT HUP INT TERM

"$binary" --help >"$test_output/help"
"$binary" >"$test_output/default-help"
cmp "$test_output/help" "$test_output/default-help"
grep -q 'Default: unlimited' "$test_output/help"
test "$("$binary" --version)" = 'input-guard 0.2.0+failure-default-dev'

expect_usage_error() {
    status=0
    "$binary" "$@" </dev/null >"$test_output/result" 2>&1 || status=$?
    if [ "$status" -ne 2 ]; then
        echo "Expected usage error for: $* (got $status)" >&2
        cat "$test_output/result" >&2
        exit 1
    fi
}

# All these paths exit before event-tap creation or any Keychain operation.
expect_usage_error unknown
expect_usage_error lock 0
expect_usage_error lock -1
expect_usage_error lock 28801
expect_usage_error lock 999999999999999999999999999
expect_usage_error lock unlimited extra
expect_usage_error trial 61
expect_usage_error trial unlimited
expect_usage_error observe unlimited
expect_usage_error observe invalid
expect_usage_error preview 0
expect_usage_error preview 61
expect_usage_error preview unlimited
expect_usage_error preview --privacy
expect_usage_error observe --lock-on-failure
expect_usage_error observe --no-lock-on-failure
expect_usage_error preview --no-lock-on-failure
expect_usage_error lock --lock-on-failure --no-lock-on-failure
expect_usage_error lock --no-lock-on-failure --no-lock-on-failure
expect_usage_error lock --lock-on-failure --lock-on-failure
expect_usage_error __worker lock
expect_usage_error __worker lock --no-lock-on-failure
expect_usage_error lock --privacy --privacy
expect_usage_error __worker trial 2 --lock-on-failure
expect_usage_error set-code extra
expect_usage_error forget-code extra
expect_usage_error set-code

# A directory at the executable path must fail before any build or installation.
mkdir -p "$test_output/install/input-guard"
status=0
INPUT_GUARD_INSTALL_DIR="$test_output/install" "$project_dir/scripts/install.sh" >"$test_output/install-result" 2>&1 || status=$?
test "$status" -eq 1
grep -q 'Refusing to install over a directory:' "$test_output/install-result"
test -d "$test_output/install/input-guard"

/usr/bin/codesign --verify --strict "$binary"
echo 'PASS: CLI validation and signature; no input blocking or Keychain access.'
"$project_dir/tests/options.sh"
"$project_dir/tests/brightness.sh"
"$project_dir/tests/supervisor.sh"

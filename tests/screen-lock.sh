#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
build_dir=${INPUT_GUARD_BUILD_DIR:-"$project_dir/.build"}
mkdir -p "$build_dir"
/usr/bin/swiftc -O -swift-version 5 -module-cache-path "$build_dir/module-cache" \
    "$project_dir/src/ScreenLock.swift" "$project_dir/tests/screen-lock/main.swift" \
    -o "$build_dir/screen-lock-tests"
"$build_dir/screen-lock-tests"

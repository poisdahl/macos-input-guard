#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
build_dir=${INPUT_GUARD_BUILD_DIR:-"$project_dir/.build"}
mkdir -p "$build_dir"
/usr/bin/swiftc -O -swift-version 5 -module-cache-path "$build_dir/module-cache" \
    "$project_dir/src/StatusOutput.swift" "$project_dir/src/UnlockSequence.swift" \
    "$project_dir/src/BlockingInstance.swift" "$project_dir/src/FailurePolicy.swift" "$project_dir/tests/SupportTests.swift" \
    -o "$build_dir/security-tests"
python3 "$project_dir/tests/security.py" "$build_dir/security-tests"

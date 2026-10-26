#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
build_dir=${INPUT_GUARD_BUILD_DIR:-"$project_dir/.build"}
architecture=${INPUT_GUARD_ARCH:-$(uname -m)}

if [ "$(uname -s)" != Darwin ]; then
    echo 'Input Guard requires macOS.' >&2
    exit 1
fi
case "$architecture" in
    x86_64|arm64) ;;
    *) echo "Unsupported architecture: $architecture" >&2; exit 1 ;;
esac
if ! /usr/bin/xcode-select -p >/dev/null 2>&1; then
    echo 'Install Apple Command Line Tools with: xcode-select --install' >&2
    exit 1
fi

mkdir -p "$build_dir"
/usr/bin/swiftc -O -swift-version 5 -target "$architecture-apple-macosx13.0" \
    -module-cache-path "$build_dir/module-cache" \
    "$project_dir"/src/*.swift -o "$build_dir/input-guard"
/usr/bin/codesign --force --sign - --identifier local.workstation.input-guard "$build_dir/input-guard"
/usr/bin/codesign --verify --strict "$build_dir/input-guard"
echo "Built $build_dir/input-guard ($architecture)."

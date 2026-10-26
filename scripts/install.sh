#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
build_dir=${INPUT_GUARD_BUILD_DIR:-"$project_dir/.build"}
install_dir=${INPUT_GUARD_INSTALL_DIR:-"$HOME/.local/bin"}

if [ -d "$install_dir/input-guard" ]; then
    echo "Refusing to install over a directory: $install_dir/input-guard" >&2
    exit 1
fi
if /usr/bin/pgrep -u "$(id -u)" -x input-guard >/dev/null 2>&1; then
    echo 'Stop your running input-guard process before installing an update.' >&2
    exit 1
fi
"$project_dir/scripts/build.sh"
mkdir -p "$install_dir"
staged_binary=$(mktemp "$install_dir/.input-guard.XXXXXX")
trap 'rm -f "$staged_binary"' EXIT HUP INT TERM
/usr/bin/install -m 755 "$build_dir/input-guard" "$staged_binary"
/usr/bin/codesign --verify --strict "$staged_binary"
/bin/mv -f "$staged_binary" "$install_dir/input-guard"
echo "Installed $install_dir/input-guard. No guard, login item or service was started."
echo "First check compatibility with: $install_dir/input-guard trial 15"

#!/usr/bin/env python3
"""Exercise real support helpers without event taps, Keychain or screen locking."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

helper = sys.argv[1]
subprocess.run([helper], check=True)

read_fd, write_fd = os.pipe()
os.close(read_fd)
try:
    result = subprocess.run([helper, "logger"], stdout=write_fd, timeout=3)
    assert result.returncode == 0, result.returncode
finally:
    os.close(write_fd)

read_fd, write_fd = os.pipe()
os.set_blocking(write_fd, False)
try:
    while True:
        os.write(write_fd, b"x" * 4096)
except BlockingIOError:
    pass
os.set_blocking(write_fd, True)
try:
    result = subprocess.run([helper, "logger"], stdout=write_fd, timeout=3)
    assert result.returncode == 0, result.returncode
finally:
    os.close(read_fd)
    os.close(write_fd)

with tempfile.TemporaryDirectory(prefix="input-guard-lock-test-") as directory:
    lock = str(Path(directory) / "instance.lock")
    first = subprocess.Popen([helper, "hold-lock", lock], stdout=subprocess.PIPE, text=True)
    try:
        assert first.stdout.readline().strip() == "READY"
        assert subprocess.run([helper, "try-lock", lock], timeout=3).returncode == 2
    finally:
        first.kill()
        first.wait(timeout=3)
    assert subprocess.run([helper, "try-lock", lock], timeout=3).returncode == 0
    Path(lock).unlink()
    Path(lock).symlink_to(Path(directory) / "target")
    assert subprocess.run([helper, "try-lock", lock], timeout=3).returncode == 2

print("PASS: closed/full output pipes; concurrent-instance rejection, crash recovery and symlink refusal.")

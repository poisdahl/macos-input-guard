#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
build_dir=${INPUT_GUARD_BUILD_DIR:-"$project_dir/.build"}
mkdir -p "$build_dir"
/usr/bin/swiftc -O -swift-version 5 -module-cache-path "$build_dir/module-cache" \
    "$project_dir/src/GuardSupervisor.swift" "$project_dir/src/ScreenLock.swift" \
    "$project_dir/src/StatusOutput.swift" "$project_dir/src/BlockingInstance.swift" "$project_dir/tests/supervisor/main.swift" \
    -o "$build_dir/supervisor-tests"
"$build_dir/supervisor-tests"
python3 - "$build_dir/supervisor-tests" <<'PY'
import os, subprocess, sys, time, socket, tempfile, fcntl
binary=sys.argv[1]
# A full output pipe must not stall lifecycle supervision. Drain only after exit.
p=subprocess.Popen([binary,'backpressure'],stdout=subprocess.PIPE,stderr=subprocess.PIPE)
try:
    assert p.wait(timeout=4)==0
finally:
    if p.poll() is None: p.kill()
    p.communicate(timeout=4)
print('PASS: blocked output does not stall supervisor')
# Worker kills only its spawned test supervisor, detects EOF and exits.
p=subprocess.Popen([binary,'orphan-supervisor'],stdout=subprocess.PIPE,stderr=subprocess.PIPE)
try:
    out,err=p.communicate(timeout=4)
    assert p.returncode == -9 and b'ORPHAN_PASS' in out, (p.returncode,out,err)
finally:
    if p.poll() is None: p.kill(); p.communicate()
print('PASS: supervisor death closes inherited lifecycle channel')
# Recover from every controlled orphan fault, while normal completion and
# pre-arm refusal must not request locking. Only test supervisors are killed.
for scenario in ['orphan-local-fault','orphan-startup-fault','orphan-normal','orphan-prearm']:
    p=subprocess.Popen([binary,scenario],stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    try:
        out,err=p.communicate(timeout=5)
        marker=b'ORPHAN_PREARM_PASS' if scenario=='orphan-prearm' else b'ORPHAN_RECOVERY_PASS:'+scenario.encode()
        assert p.returncode == -9 and marker in out, (scenario,p.returncode,out,err)
    finally:
        if p.poll() is None: p.kill();p.communicate(timeout=4)
print('PASS: orphan faults tear down before locking; normal/pre-arm exits do not relock')
# Parent exits after receiving Arm, before acknowledging. The worker must recover
# without assuming a failed exchange means no supervisor ever armed.
parent_code = r"""
import os,socket,sys
parent,child=socket.socketpair()
actions=[(os.POSIX_SPAWN_CLOSE,parent.fileno()),(os.POSIX_SPAWN_DUP2,child.fileno(),3)]
if child.fileno()!=3: actions.append((os.POSIX_SPAWN_CLOSE,child.fileno()))
os.posix_spawn(sys.argv[1],[sys.argv[1],'worker-orphan-arm-failure'],os.environ,file_actions=actions)
child.close();parent.settimeout(3)
assert parent.recv(256).startswith(b'A:')
os._exit(0)
"""
p=subprocess.Popen([sys.executable,'-c',parent_code,binary],stdout=subprocess.PIPE,stderr=subprocess.PIPE)
try:
    out,err=p.communicate(timeout=5)
    assert p.returncode==0 and b'ORPHAN_ARM_FAILURE_PASS' in out, (p.returncode,out,err)
finally:
    if p.poll() is None: p.kill();p.communicate(timeout=4)
print('PASS: orphaned worker recovers after lost arm acknowledgement')
with tempfile.TemporaryDirectory(prefix='input-guard-reservation-test-') as tmp:
    path=os.path.join(tmp,'instance.lock')
    p=subprocess.Popen([binary,'reservation-supervisor',path],stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    try:
        out,err=p.communicate(timeout=4)
        assert p.returncode == -9 and b'RESERVATION_PASS' in out, (p.returncode,out,err)
    finally:
        if p.poll() is None: p.kill();p.communicate()
    with open(path,'r+') as f:
        fcntl.flock(f,fcntl.LOCK_EX|fcntl.LOCK_NB)
print('PASS: worker retains singleton after supervisor death, releases it on exit')
# A live parent withholds completion ACK. Timeout must NOT transfer lock ownership.
parent,child=socket.socketpair()
readout,writeout=os.pipe()
actions=[(os.POSIX_SPAWN_CLOSE,parent.fileno()),(os.POSIX_SPAWN_DUP2,child.fileno(),3)]
if child.fileno()!=3: actions.append((os.POSIX_SPAWN_CLOSE,child.fileno()))
actions += [(os.POSIX_SPAWN_DUP2,writeout,1),(os.POSIX_SPAWN_CLOSE,readout),(os.POSIX_SPAWN_CLOSE,writeout)]
pid=os.posix_spawn(binary,[binary,'worker-ack-timeout'],os.environ,file_actions=actions)
child.close();os.close(writeout);parent.settimeout(3)
reaped=False
try:
    assert parent.recv(256).startswith(b'A:')
    parent.sendall(b'R')
    assert parent.recv(256).startswith(b'C:')
    deadline=time.monotonic()+4
    while time.monotonic()<deadline:
        waited,status=os.waitpid(pid,os.WNOHANG)
        if waited==pid:
            reaped=True
            assert os.waitstatus_to_exitcode(status)==0,status
            break
        time.sleep(.02)
    assert reaped
    assert b'OWNERSHIP_PASS' in os.read(readout,4096)
finally:
    if not reaped: os.kill(pid,9);os.waitpid(pid,0)
    parent.close();os.close(readout)
print('PASS: delayed completion ACK does not transfer fallback ownership')
PY

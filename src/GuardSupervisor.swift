// SPDX-License-Identifier: MIT
import Foundation
import Darwin

// Only lifecycle messages cross this private channel. Codes stay in the worker.
private let controlFD: Int32 = 3
private var supervisorSignal: Int32 = 0

private func sendControl(_ fd: Int32, _ text: String) -> Bool {
    let bytes = Array(text.utf8)
    return bytes.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) == $0.count }
}

final class GuardWorkerChannel {
    private let supervisorPID = getppid()
    private var armingAttempted = false
    var supervisorHasExited: Bool { supervisorPID > 1 && getppid() != supervisorPID }
    init?() {
        var kind: Int32 = 0
        var size = socklen_t(MemoryLayout<Int32>.size)
        guard getsockopt(controlFD, SOL_SOCKET, SO_TYPE, &kind, &size) == 0,
              kind == SOCK_STREAM else { return nil }
        _ = fcntl(controlFD, F_SETFD, FD_CLOEXEC)
        _ = fcntl(controlFD, F_SETFL, O_NONBLOCK)
        signal(SIGPIPE, SIG_IGN)
    }

    private func exchange(_ command: String, expecting: UInt8) -> Bool {
        guard sendControl(controlFD, "\(command):\(ProcessInfo.processInfo.systemUptime)\n") else { return false }
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        while ProcessInfo.processInfo.systemUptime < deadline {
            var byte: UInt8 = 0
            let count = read(controlFD, &byte, 1)
            if count == 1 { return byte == expecting }
            if count == 0 || (count < 0 && errno != EAGAIN && errno != EINTR) { return false }
            usleep(10_000)
        }
        return false
    }

    func arm() -> Bool {
        armingAttempted = true
        return exchange("A", expecting: 82) // Ready
    }

    // Called only on controlled exits. A channel error alone never transfers
    // ownership; confirmed parent death does. Teardown always precedes locking.
    func finish(status: Int32, teardown: () -> Void, lockAction: () -> Void) {
        teardown()
        if status != 0 && armingAttempted && supervisorHasExited { lockAction() }
    }
    func complete() -> Bool { exchange("C", expecting: 68) } // Disarm accepted

    func heartbeat() -> Bool {
        var byte: UInt8 = 0
        let readCount = read(controlFD, &byte, 1)
        // No unsolicited messages are valid. EOF means the supervisor is gone.
        guard readCount < 0, errno == EAGAIN || errno == EINTR else { return false }
        return sendControl(controlFD, "H:\(ProcessInfo.processInfo.systemUptime)\n")
    }
}

// This parent owns its child until waitpid reaps it. No global PID searches or
// signalling after reaping; no tap or overlay is ever owned by the supervisor.
func superviseGuard(executable: String, arguments: [String], heartbeatTimeout: Double = 5,
                    reservationFD: Int32? = nil,
                    lockAction: () -> Void) -> Int32 {
    var armed = false
    var reaped = false
    var terminal = termios()
    let savedTerminal = tcgetattr(STDIN_FILENO, &terminal) == 0
    defer {
        // A pre-arm getpass may have been killed before restoring echo. Never
        // overwrite terminal changes after an armed run, or before confirmed exit.
        if savedTerminal && reaped && !armed { _ = tcsetattr(STDIN_FILENO, TCSANOW, &terminal) }
    }
    var sockets = [Int32](repeating: -1, count: 2)
    guard socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets) == 0 else { return 1 }
    defer { close(sockets[0]) }
    for fd in sockets { _ = fcntl(fd, F_SETFD, FD_CLOEXEC) }
    _ = fcntl(sockets[0], F_SETFL, O_NONBLOCK)
    signal(SIGPIPE, SIG_IGN)
    supervisorSignal = 0
    for number in [SIGTERM, SIGINT, SIGHUP] {
        signal(number) { supervisorSignal = $0 }
    }
    defer {
        for number in [SIGTERM, SIGINT, SIGHUP] { signal(number, SIG_DFL) }
    }

    var actions: posix_spawn_file_actions_t?
    var attributes: posix_spawnattr_t?
    guard posix_spawn_file_actions_init(&actions) == 0,
          posix_spawnattr_init(&attributes) == 0 else { close(sockets[1]); return 1 }
    defer { posix_spawn_file_actions_destroy(&actions); posix_spawnattr_destroy(&attributes) }
    // Explicit stdio inheritance preserves the foreground Terminal for getpass.
    for fd in [STDIN_FILENO, STDOUT_FILENO, STDERR_FILENO] {
        posix_spawn_file_actions_adddup2(&actions, fd, fd)
    }
    posix_spawn_file_actions_addclose(&actions, sockets[0])
    posix_spawn_file_actions_adddup2(&actions, sockets[1], controlFD)
    if sockets[1] != controlFD { posix_spawn_file_actions_addclose(&actions, sockets[1]) }
    if let reservationFD {
        // Same locked open-file description survives either process dying.
        posix_spawn_file_actions_adddup2(&actions, reservationFD, 4)
    }
    var defaults = sigset_t()
    sigemptyset(&defaults)
    for number in [SIGTERM, SIGINT, SIGHUP, SIGPIPE, SIGALRM] { sigaddset(&defaults, number) }
    posix_spawnattr_setsigdefault(&attributes, &defaults)
    var mask = sigset_t(); sigemptyset(&mask)
    posix_spawnattr_setsigmask(&attributes, &mask)
    posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_CLOEXEC_DEFAULT))
    let argv = ([executable] + arguments).map { strdup($0) } + [nil]
    defer { argv.forEach { free($0) } }
    let environment = ProcessInfo.processInfo.environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
    defer { environment.forEach { free($0) } }
    var child: pid_t = 0
    let spawnResult = argv.withUnsafeBufferPointer { pointer in
        environment.withUnsafeBufferPointer { env in
            posix_spawn(&child, executable, &actions, &attributes,
                        UnsafeMutablePointer(mutating: pointer.baseAddress!), UnsafeMutablePointer(mutating: env.baseAddress!))
        }
    }
    close(sockets[1])
    guard spawnResult == 0 else { return 1 }
    report("SUPERVISOR pid=\(getpid()) worker_pid=\(child); native lock fallback is best effort")

    var completing = false
    var completionTime = 0.0
    var lastHeartbeat = 0.0
    var buffer = Data()
    var fault: String?
    var prearmEOFTime: TimeInterval?
    var childStatus: Int32 = 0
    while fault == nil {
        if supervisorSignal != 0 { fault = "supervisor termination signal"; break }
        var eof = false
        var bytes = [UInt8](repeating: 0, count: 256)
        // Bound each drain so a faulty worker cannot starve timeout/reaping.
        for _ in 0..<8 {
            let count = read(sockets[0], &bytes, bytes.count)
            if count > 0 { buffer.append(contentsOf: bytes.prefix(count)) }
            else if count == 0 { eof = true; break }
            else if errno == EAGAIN || errno == EINTR { break }
            else { fault = "control channel failed"; break }
        }
        if buffer.count > 1024 { fault = "invalid control stream" }
        while fault == nil, let newline = buffer.firstIndex(of: 10) {
            let line = String(decoding: buffer[..<newline], as: UTF8.self)
            buffer.removeSubrange(...newline)
            let parts = line.split(separator: ":", omittingEmptySubsequences: false)
            let now = ProcessInfo.processInfo.systemUptime
            guard parts.count == 2, let stamp = Double(parts[1]), stamp.isFinite,
                  stamp <= now + 0.05,
                  parts[0] == "H" || now - stamp <= min(2, heartbeatTimeout),
                  !armed || stamp >= lastHeartbeat else { fault = "stale or invalid heartbeat"; break }
            switch parts[0] {
            case "A" where !armed:
                armed = true; lastHeartbeat = stamp
                if !sendControl(sockets[0], "R") { fault = "arm acknowledgement failed" }
            case "H" where armed && !completing:
                lastHeartbeat = stamp
            case "C" where armed && !completing:
                // Explicit normal completion is only provisional until a timely,
                // successful child exit proves its tap/windows have gone away.
                completing = true; completionTime = now
                if !sendControl(sockets[0], "D") { fault = "completion acknowledgement failed" }
            default: fault = "unexpected lifecycle message"
            }
        }
        let waited = waitpid(child, &childStatus, WNOHANG)
        if waited == child {
            reaped = true
            if !armed { return childStatus & 0x7f == 0 ? (childStatus >> 8) & 0xff : 1 }
            if fault == nil && completing && childStatus == 0,
               ProcessInfo.processInfo.systemUptime - completionTime <= 2 { return 0 }
            fault = fault ?? "guard exited unexpectedly"
        } else if waited < 0 && errno != EINTR {
            // Child ownership is no longer certain. Never signal this PID.
            report("Cannot confirm worker termination; no native lock request made.")
            return 3
        }
        if supervisorSignal != 0 { fault = "supervisor termination signal" }
        let now = ProcessInfo.processInfo.systemUptime
        if armed && !completing && now - lastHeartbeat > heartbeatTimeout { fault = "guard heartbeat expired" }
        if completing && now - completionTime > 2 { fault = "guard did not exit after completion" }
        if eof && !completing && !reaped {
            if armed { fault = "guard control channel closed" }
            else {
                // EOF can precede waitpid readiness. Let a preflight refusal
                // finish and preserve its exit status, without waiting forever.
                if prearmEOFTime == nil { prearmEOFTime = now }
                if now - prearmEOFTime! >= 0.5 { fault = "guard control channel closed" }
            }
        }
        if fault == nil { usleep(50_000) }
    }
    if !reaped {
        // Confirm worker exit before requesting native locking.
        kill(child, SIGKILL)
        var result: pid_t = 0
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        repeat {
            result = waitpid(child, &childStatus, WNOHANG)
            if result == 0 || (result < 0 && errno == EINTR) { usleep(10_000) }
        } while (result == 0 || (result < 0 && errno == EINTR)) && ProcessInfo.processInfo.systemUptime < deadline
        guard result == child else {
            report("Worker termination could not be confirmed; lock state unconfirmed.")
            return 3
        }
        reaped = true
    }
    guard armed else { return 1 }
    report("PROTECTION LOST: \(fault ?? "unknown failure"). Worker ended; requesting macOS Lock Screen once.")
    lockAction()
    return 3
}

func requestNativeLock() {
    // Independent backstop for a stuck Accessibility request; this process has
    // no active input tap or privacy windows when this function is called.
    signal(SIGALRM, SIG_DFL); alarm(12)
    switch ScreenLocker().request() {
    case .accepted: report("macOS lock request accepted; lock state unconfirmed.")
    case .unavailable: report("Lock Screen action unavailable; lock state unconfirmed. Lock macOS manually.")
    case .unconfirmed(let code): report("Lock Screen request outcome unconfirmed (\(code)); lock state unconfirmed. Check macOS manually.")
    case .rejected(let code): report("Lock Screen request failed (\(code)); lock state unconfirmed. Lock macOS manually.")
    }
    alarm(0)
}

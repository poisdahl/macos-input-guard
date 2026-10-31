// SPDX-License-Identifier: MIT
// This harness NEVER calls requestNativeLock, reads codes or creates event taps.
import Foundation
import Darwin

let output = StatusOutput()
func report(_ text: String) { output.report(text) }
atexit { output.flush() }
let mode = CommandLine.arguments.dropFirst().first ?? "suite"
let executable = Bundle.main.executablePath!
if mode.hasPrefix("worker-") {
    let scenario = String(mode.dropFirst(7))
    if scenario == "preflight" { exit(2) }
    if scenario == "prearm-close" { close(3); usleep(150_000); exit(2) }
    if scenario.hasPrefix("prearm-terminal-") {
        var terminal = termios()
        precondition(tcgetattr(STDIN_FILENO, &terminal) == 0)
        terminal.c_lflag &= ~tcflag_t(ECHO)
        precondition(tcsetattr(STDIN_FILENO, TCSANOW, &terminal) == 0)
        let number = scenario.hasSuffix("int") ? SIGINT : (scenario.hasSuffix("hup") ? SIGHUP : SIGTERM)
        kill(getppid(), number)
        sleep(3); exit(54)
    }
    guard let channel = GuardWorkerChannel() else { exit(41) }
    if scenario == "orphan-prearm" || scenario == "orphan-arm-failure" {
        alarm(4)
        if scenario == "orphan-prearm" {
            kill(getppid(), SIGKILL); usleep(150_000)
        } else {
            // A separate test parent reads A then exits without sending Ready.
            guard !channel.arm() else { exit(52) }
            usleep(150_000)
        }
        guard channel.supervisorHasExited else { exit(53) }
        var tornDown = false
        var calls = 0
        channel.finish(status: 1, teardown: { tornDown = true }) {
            precondition(tornDown); calls += 1
        }
        precondition(tornDown && calls == (scenario == "orphan-prearm" ? 0 : 1))
        print(scenario == "orphan-prearm" ? "ORPHAN_PREARM_PASS" : "ORPHAN_ARM_FAILURE_PASS")
        exit(0)
    }
    guard channel.arm() else { exit(41) }
    switch scenario {
    case "clean":
        guard channel.heartbeat(), channel.complete() else { exit(42) }
        exit(0)
    case "zero": exit(0)
    case "local-fault":
        var tornDown = false
        channel.finish(status: 3, teardown: { tornDown = true }) {
            fatalError("A live supervisor still owns fallback")
        }
        precondition(tornDown); exit(3)
    case "orphan-local-fault", "orphan-startup-fault", "orphan-normal":
        alarm(4)
        if scenario == "orphan-normal" { precondition(channel.complete()) }
        kill(getppid(), SIGKILL); usleep(150_000)
        precondition(channel.supervisorHasExited)
        var resources = scenario == "orphan-startup-fault" ? 0 : 2
        var calls = 0
        channel.finish(status: scenario == "orphan-normal" ? 0 : 3,
                       teardown: { resources = 0 }) {
            precondition(resources == 0); calls += 1
        }
        precondition(resources == 0 && calls == (scenario == "orphan-normal" ? 0 : 1))
        print("ORPHAN_RECOVERY_PASS:" + scenario)
        exit(0)
    case "expiry":
        for _ in 0..<3 { usleep(80_000); guard channel.heartbeat() else { exit(42) } }
        guard channel.complete() else { exit(42) }
        exit(0)
    case "queued-heartbeats":
        // Pause only this harness's supervisor; the worker remains healthy.
        kill(getppid(), SIGSTOP)
        for _ in 0..<7 {
            usleep(900_000)
            guard channel.heartbeat() else { kill(getppid(), SIGCONT); exit(42) }
        }
        kill(getppid(), SIGCONT)
        usleep(150_000)
        guard channel.complete() else { exit(42) }
        exit(0)
    case "parent-term": kill(getppid(), SIGTERM); sleep(3)
    case "ack-timeout":
        guard !channel.complete(), !channel.supervisorHasExited else { exit(48) }
        print("OWNERSHIP_PASS"); exit(0)
    case "crash": raise(SIGKILL)
    case "hang": raise(SIGSTOP)
    case "late": usleep(900_000); _ = channel.complete()
    case "cleanup-hang":
        guard channel.complete() else { exit(43) }
        raise(SIGSTOP)
    case "stale":
        let line = "H:\(ProcessInfo.processInfo.systemUptime - 60)\n"
        _ = line.withCString { write(3, $0, strlen($0)) }
        sleep(3)
    case "broken": close(3); sleep(3)
    case "orphan":
        // The only process signalled is this harness worker's own supervisor.
        kill(getppid(), SIGKILL)
        usleep(150_000)
        guard !channel.heartbeat(), channel.supervisorHasExited else { exit(44) }
        print("ORPHAN_PASS")
        exit(0)
    case "reservation":
        let inherited = try! BlockingInstance(inheritedDescriptor: 4)
        kill(getppid(), SIGKILL); usleep(150_000)
        guard channel.supervisorHasExited, !channel.heartbeat() else { exit(49) }
        do {
            _ = try BlockingInstance(path: CommandLine.arguments[2])
            exit(50)
        } catch BlockingInstanceError.alreadyRunning {
            print("RESERVATION_PASS")
        } catch { exit(51) }
        withExtendedLifetime(inherited) {}
        exit(0)
    default: exit(45)
    }
    exit(46)
}
if mode == "reservation-supervisor" {
    let reservation = try! BlockingInstance(path: CommandLine.arguments[2])
    let result = superviseGuard(executable: executable, arguments: ["worker-reservation", CommandLine.arguments[2]],
                               heartbeatTimeout: 0.4, reservationFD: reservation.inheritedDescriptor) {
        fatalError("Reservation test supervisor must have exited")
    }
    withExtendedLifetime(reservation) {}
    exit(result)
}
if ["orphan-supervisor", "orphan-local-fault", "orphan-startup-fault", "orphan-normal", "orphan-prearm"].contains(mode) {
    let worker = mode == "orphan-supervisor" ? "worker-orphan" : "worker-" + mode
    exit(superviseGuard(executable: executable, arguments: [worker], heartbeatTimeout: 0.4) {
        fatalError("Orphan supervisor must be gone; no lock callback expected")
    })
}
if mode == "backpressure" {
    for _ in 0..<100 { report(String(repeating: "x", count: 8190)) }
    var calls = 0
    let result = superviseGuard(executable: executable, arguments: ["worker-crash"], heartbeatTimeout: 0.4) { calls += 1 }
    exit(result == 3 && calls == 1 ? 0 : 47)
}
if mode.hasPrefix("terminal-") || mode == "queued-heartbeats" {
    var calls = 0
    let worker = mode == "queued-heartbeats" ? mode : "prearm-" + mode
    let result = superviseGuard(executable: executable, arguments: ["worker-" + worker]) { calls += 1 }
    precondition(result == (mode == "queued-heartbeats" ? 0 : 1) && calls == 0)
    print("PASS: " + mode)
    exit(0)
}
let cases: [(String, Int32, Int)] = [
    ("preflight", 2, 0), ("prearm-close", 2, 0), ("local-fault", 3, 1), ("clean", 0, 0), ("expiry", 0, 0), ("zero", 3, 1), ("parent-term", 3, 1),
    ("crash", 3, 1), ("hang", 3, 1), ("late", 3, 1),
    ("cleanup-hang", 3, 1), ("stale", 3, 1), ("broken", 3, 1)
]
for (scenario, expected, expectedCalls) in cases {
    var calls = 0
    let started = ProcessInfo.processInfo.systemUptime
    let result = superviseGuard(executable: executable, arguments: ["worker-" + scenario], heartbeatTimeout: 0.4) {
        calls += 1
        // Any still-unreaped child means fallback was called too early.
        var status: Int32 = 0
        precondition(waitpid(-1, &status, WNOHANG) == -1 && errno == ECHILD)
    }
    precondition(result == expected && calls == expectedCalls, "FAILED \(scenario): \(result), \(calls)")
    precondition(ProcessInfo.processInfo.systemUptime - started < 4)
    print("PASS: \(scenario)")
}
for _ in 0..<10 {
    precondition(superviseGuard(executable: executable, arguments: ["worker-preflight"]) {
        fatalError("Pre-arm exit must not request locking")
    } == 2)
}
print("PASS: repeated pre-arm exit preserves status")

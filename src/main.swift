// SPDX-License-Identifier: MIT
// Session event-tap foundation adapted from choiyounggi/mac-inputlock; see THIRD_PARTY_NOTICES.md.
// A session event filter, not a macOS authentication boundary.
import Foundation
import CoreGraphics
import ApplicationServices
import Carbon
import Darwin
import Security
import AppKit

let statusOutput = StatusOutput()
func report(_ message: String) {
    statusOutput.report(message)
}
atexit { statusOutput.flush() }

func processPath(_ pid: Int32) -> String {
    var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
    guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return "<unavailable>" }
    return String(cString: buffer)
}

func keyboardLayoutID() -> String {
    let source = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
    guard let value = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return "unknown" }
    return Unmanaged<CFString>.fromOpaque(value).takeUnretainedValue() as String
}

func readCode(_ prompt: String) -> [UInt8]? {
    guard let pointer = getpass(prompt) else { return nil }
    let length = strlen(pointer)
    let copy = UnsafeBufferPointer(start: pointer, count: length).map { UInt8(bitPattern: $0) }
    // getpass uses one static buffer; copy before the confirmation call, then erase it.
    memset(pointer, 0, length)
    return copy
}

func validCode(_ code: [UInt8]) -> Bool {
    (8...64).contains(code.count) && code.allSatisfy { (97...122).contains($0) || (48...57).contains($0) }
}

func confirmedCode(_ prompt: String) -> [UInt8] {
    guard isatty(STDIN_FILENO) == 1 else {
        report("Code entry requires an interactive Terminal; codes are never accepted in arguments or pipes.")
        exit(2)
    }
    guard let first = readCode(prompt), validCode(first) else {
        report("Invalid code. Nothing changed or blocked.")
        exit(2)
    }
    guard let second = readCode("Confirm code: "), first == second else {
        report("Codes did not match. Nothing changed or blocked.")
        exit(2)
    }
    return first
}

// Use the local file-based default Keychain with its normal access controls.
// Do not add Data Protection, sync, access-group or unrestricted ACL attributes.
let codeIdentity: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "local.workstation.input-guard",
    kSecAttrAccount as String: "unlock-code"
]

func requireKeychainSuccess(_ status: OSStatus) {
    guard status == errSecSuccess else {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown error"
        report("Keychain error (\(status)): \(message). Nothing is blocked.")
        exit(1)
    }
}

func defaultKeychain() -> SecKeychain {
    var keychain: SecKeychain?
    requireKeychainSuccess(SecKeychainCopyDefault(&keychain))
    guard let keychain else {
        report("Default Keychain is unavailable. Nothing is blocked.")
        exit(1)
    }
    return keychain
}

func codeQuery(_ keychain: SecKeychain) -> [String: Any] {
    var query = codeIdentity
    query[kSecMatchSearchList as String] = [keychain]
    return query
}

func savedCode() -> [UInt8]? {
    var query = codeQuery(defaultKeychain())
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    requireKeychainSuccess(status)
    guard let data = result as? Data, validCode(Array(data)) else {
        report("Saved code has an invalid format. Run input-guard set-code to replace it. Nothing is blocked.")
        exit(1)
    }
    return Array(data)
}

func saveCode(_ code: [UInt8]) {
    let keychain = defaultKeychain()
    let value = [kSecValueData as String: Data(code)]
    let status = SecItemUpdate(codeQuery(keychain) as CFDictionary, value as CFDictionary)
    if status == errSecItemNotFound {
        var item = codeIdentity
        item[kSecUseKeychain as String] = keychain
        item[kSecAttrLabel as String] = "Input Guard unlock code"
        item[kSecValueData as String] = Data(code)
        requireKeychainSuccess(SecItemAdd(item as CFDictionary, nil))
    } else {
        requireKeychainSuccess(status)
    }
}

// Physical positions shared by the explicitly supported Apple QWERTY layouts.
let supportedLayouts = ["com.apple.keylayout.Norwegian", "com.apple.keylayout.NorwegianExtended",
                        "com.apple.keylayout.US", "com.apple.keylayout.ABC"]
let keyCharacters: [Int64: UInt8] = [
    0:97, 1:115, 2:100, 3:102, 4:104, 5:103, 6:122, 7:120, 8:99, 9:118,
    11:98, 12:113, 13:119, 14:101, 15:114, 16:121, 17:116,
    18:49, 19:50, 20:51, 21:52, 22:54, 23:53, 25:57, 26:55, 28:56, 29:48,
    31:111, 32:117, 34:105, 35:112, 37:108, 38:106, 40:107, 45:110, 46:109
]

let options: GuardOptions
do { options = try GuardOptions(arguments: Array(CommandLine.arguments.dropFirst())) }
catch { report("Invalid options. Run input-guard --help."); exit(2) }
let isSupervisedWorker = options.isSupervisedWorker
let privacy = options.privacy
let lockOnFailure = options.lockOnFailure
let args = options.args
let mode = options.mode
let workerChannel = isSupervisedWorker ? GuardWorkerChannel() : nil
if isSupervisedWorker && workerChannel == nil { report("Private supervision channel unavailable."); exit(2) }
// Every controlled post-arm failure removes its resources before an orphaned
// worker can request locking; the live supervisor remains the normal owner.
func finishWorker(status: Int32, teardown: () -> Void) {
    if let workerChannel {
        workerChannel.finish(status: status, teardown: teardown, lockAction: requestNativeLock)
    } else { teardown() }
}
var blockingInstance: BlockingInstance?
if isSupervisedWorker {
    do { blockingInstance = try BlockingInstance(inheritedDescriptor: 4) }
    catch { report("Inherited guard reservation unavailable."); exit(2) }
}
if mode == "--version" {
    report("input-guard 0.2.0+failure-default-dev")
    exit(0)
}
if mode == "help" || mode == "--help" {
    report("""
    input-guard lock [seconds]     Use saved code, or ask for a hidden temporary code.
                                  Default: unlimited; timed maximum: 28800 (8 hours).
    input-guard lock unlimited     Block with no automatic expiry; same unlock code.
    input-guard set-code           Save or replace your code in the local macOS Keychain.
    input-guard forget-code        Remove only this guard's saved code.
    input-guard trial [seconds]    No code; automatically releases after 1...60 seconds.
    input-guard observe [seconds]  Count event types/sources for 1...60 seconds; no blocking.
    input-guard preview [seconds]  Preview the privacy overlay for 1...60 seconds; no blocking.
    Options for lock/trial (qualify your setup first):
      --privacy                   Show a frosted overlay; off by default.
      --lock-on-failure            Request macOS locking on faults; default for lock.
      --no-lock-on-failure         Disable fallback; failures release input without macOS locking.
    trial has no failure locking unless --lock-on-failure is explicit.
    Code unlock and timed expiry release normally. Terminating a supervised lock requests macOS locking.
    input-guard probe              Show permissions, Secure Input and keyboard layout.
    input-guard --version          Show the release version.

    Codes use 8...64 lowercase letters/digits (a-z, 0-9).
    To unlock, type that code anywhere without Shift/Caps Lock, then release the last key.
    No Enter is needed. Codes are never printed. Only set-code saves a code.
    Saved-code changes apply to future runs; an active guard keeps its current code.
    Supports Apple Norwegian, Norwegian Extended, US and ABC QWERTY layouts.
    Unmodified display/keyboard brightness controls remain available; Fn is allowed.
    Timed runs expire automatically; unlimited has no expiry. Process exit removes the filter.
    This is an input guard, not the macOS security lock. Screen contents remain visible.
    """)
    exit(0)
}
if mode == "probe" {
    let trusted = AXIsProcessTrusted()
    let availability = trusted ? String(ScreenLocker().available()) : "unavailable_without_accessibility"
    report("accessibility=\(trusted) secure_input=\(IsSecureEventInputEnabled()) layout=\(keyboardLayoutID()) lock_action_available=\(availability)")
    exit(0)
}
if mode == "set-code" || mode == "forget-code" {
    guard args.count == 1 else {
        report("This command accepts no arguments; enter codes only at the hidden prompt.")
        exit(2)
    }
    if mode == "set-code" {
        saveCode(confirmedCode("New saved unlock code (8...64 a-z/0-9): "))
        report("Code saved in the local macOS Keychain. Future lock runs use it automatically.")
    } else {
        let status = SecItemDelete(codeQuery(defaultKeychain()) as CFDictionary)
        if status != errSecItemNotFound { requireKeychainSuccess(status) }
        report(status == errSecItemNotFound ? "No saved code found." : "Saved code removed. Future lock runs ask for a temporary code.")
    }
    exit(0)
}
let durationArgument = args.count == 2 ? args[1] : (mode == "lock" ? "unlimited" : "30")
let seconds = Int(durationArgument)
let unlimited = mode == "lock" && durationArgument == "unlimited"
guard ["observe", "trial", "lock", "preview"].contains(mode), args.count <= 2,
      unlimited || (seconds.map { (1...(mode == "lock" ? 28800 : 60)).contains($0) } ?? false) else {
    report("Invalid mode or duration. Run input-guard --help.")
    exit(2)
}
if mode == "preview" {
    signal(SIGALRM, SIG_DFL)
    alarm(UInt32(seconds! + 2))
    var lostCoverage = false
    let overlay = PrivacyOverlay(instruction: "Input Guard privacy preview\nInput is not blocked. This preview closes automatically.", coverageLost: {
        lostCoverage = true; stopGuardLoop()
    })
    guard overlay.show() else { overlay.hide(); report("Cannot cover the current displays."); exit(1) }
    let timer = Timer.scheduledTimer(withTimeInterval: Double(seconds!), repeats: false) { _ in stopGuardLoop() }
    report("PREVIEW pid=\(getpid()) duration=\(seconds!)s; input is not blocked; reduce_transparency=\(NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)")
    NSApplication.shared.run()
    timer.invalidate(); overlay.hide(); alarm(0)
    report(lostCoverage ? "Preview ended: display coverage lost; overlays removed." : "Preview ended; overlays removed.")
    exit(lostCoverage ? 3 : 0)
}
// The supervisor retains this lock until its fallback has completed. A worker
// uses the parent's reservation rather than competing with it.
if ["lock", "trial"].contains(mode) && !isSupervisedWorker {
    do { blockingInstance = try BlockingInstance(path: BlockingInstance.defaultPath()) }
    catch { report("Another guard is active, or its instance lock is unavailable. Nothing is blocked."); exit(1) }
}
guard AXIsProcessTrusted() else {
    if mode == "lock" {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
    report("Accessibility permission required for this executable or its launching app (e.g. Terminal). Enable it in System Settings > Privacy & Security > Accessibility, then retry. Nothing is blocked.")
    exit(1)
}
if lockOnFailure && !isSupervisedWorker {
    guard ScreenLocker().available() else {
        report("Native Lock Screen action unavailable (requires Accessibility and the system Finder’s English Lock Screen action). Nothing is blocked. Use --no-lock-on-failure only if you accept failure releasing input without macOS locking."); exit(1)
    }
    let executable = processPath(getpid())
    guard executable != "<unavailable>" else { report("Cannot locate the guard executable."); exit(1) }
    let result = superviseGuard(executable: executable, arguments: options.workerArguments,
                                reservationFD: blockingInstance?.inheritedDescriptor,
                                lockAction: requestNativeLock)
    withExtendedLifetime(blockingInstance) {}
    exit(result)
}
guard !IsSecureEventInputEnabled() else {
    report("Secure Input is active; reliable keyboard interception is unavailable. Nothing is blocked.")
    exit(1)
}

let initialLayout = keyboardLayoutID()
var unlockCode: [UInt8] = []
if mode == "lock" {
    guard supportedLayouts.contains(initialLayout) else {
        report("Unsupported keyboard layout: \(initialLayout). Nothing is blocked.")
        exit(2)
    }
    if let stored = savedCode() {
        unlockCode = stored
        report("Using saved code from the local macOS Keychain.")
    } else {
        unlockCode = confirmedCode("Temporary unlock code (8...64 a-z/0-9): ")
    }
    // Terminal can release password-entry Secure Input asynchronously after echo is restored.
    // Wait for the real state to clear; never disable or bypass it.
    let readyDeadline = ProcessInfo.processInfo.systemUptime + 3
    if IsSecureEventInputEnabled() { report("Waiting briefly for Terminal to finish hidden code entry; nothing is blocked yet.") }
    while IsSecureEventInputEnabled() && ProcessInfo.processInfo.systemUptime < readyDeadline {
        usleep(50_000)
    }
    guard !IsSecureEventInputEnabled() else {
        report("Secure Input is still active after code entry. Nothing is blocked.")
        exit(1)
    }
    let currentLayout = keyboardLayoutID()
    guard currentLayout == initialLayout else {
        report("Keyboard layout changed from \(initialLayout) to \(currentLayout). Nothing is blocked.")
        exit(1)
    }
}

var counts: [String: Int] = [:]
var brightnessCounts: [BrightnessControl: Int] = [:]
var brightnessPassthrough = BrightnessPassthrough()
var stopReason = "deadline"
var exitStatus: Int32 = 0
var normalCompletion = false
let blocking = mode != "observe"
var enteredCode: [UInt8] = []
var lastCodeKeyTime: TimeInterval = 0
var unlockingKey: Int64?
let eventTypes: [CGEventType] = [
    .keyDown, .keyUp, .flagsChanged, .leftMouseDown, .leftMouseUp,
    .rightMouseDown, .rightMouseUp, .mouseMoved, .leftMouseDragged,
    .rightMouseDragged, .scrollWheel, .otherMouseDown, .otherMouseUp, .otherMouseDragged
]
let requiredOrdinaryMask = eventTypes.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
let callback: CGEventTapCallBack = { _, type, event, _ in
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        stopReason = "event tap disabled; protection lost"
        exitStatus = 3
        stopGuardLoop()
        return Unmanaged.passUnretained(event)
    }
    let pid = event.getIntegerValueField(.eventSourceUnixProcessID)
    let key = "\(type.rawValue):\(pid)"
    if mode != "lock", counts[key] != nil || counts.count < 256 { counts[key, default: 0] += 1 }
    if let brightness = brightnessPassthrough.decision(for: event, currentFlags: {
        CGEventSource.flagsState(.combinedSessionState).union(CGEventSource.flagsState(.hidSystemState))
    }) {
        if mode != "lock" { brightnessCounts[brightness.control, default: 0] += 1 }
        // A lighting adjustment is not part of code entry. Never forward
        // modifier changes or synthesize replacement input to make it work.
        if blocking && brightness.release {
            event.flags = CGEventFlags(rawValue: event.flags.rawValue & ~brightnessForbiddenFlags)
        }
        enteredCode.removeAll(keepingCapacity: true)
        return Unmanaged.passUnretained(event)
    }
    if mode == "lock", pid == 0 {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyUp, let finalKey = unlockingKey, keyCode == finalKey {
            stopReason = "unlock code accepted"
            normalCompletion = true
            stopGuardLoop()
        } else if type == .keyDown, unlockingKey == nil,
                  event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastCodeKeyTime > 10 { enteredCode.removeAll(keepingCapacity: true) }
            lastCodeKeyTime = now
            let forbidden: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift, .maskAlphaShift]
            if !event.flags.intersection(forbidden).isEmpty {
                enteredCode.removeAll(keepingCapacity: true)
            } else if keyCode == 51 { // Backspace corrects a partial code.
                if !enteredCode.isEmpty { enteredCode.removeLast() }
            } else if let character = keyCharacters[keyCode] {
                enteredCode.append(character)
                if enteredCode.count > unlockCode.count { enteredCode.removeFirst() }
                if enteredCode == unlockCode { unlockingKey = keyCode }
            } else {
                enteredCode.removeAll(keepingCapacity: true)
            }
        } else if type == .flagsChanged {
            enteredCode.removeAll(keepingCapacity: true)
        }
    }
    return blocking ? nil : Unmanaged.passUnretained(event)
}
if let workerChannel, !workerChannel.arm() {
    report("Supervisor did not acknowledge arming. Nothing is blocked.")
    finishWorker(status: 1, teardown: {})
    exit(1)
}
guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                // Include system gesture events delivered to this tap, without
                                // assuming AppKit gesture numbers map to Quartz event types.
                                options: blocking ? .defaultTap : .listenOnly, eventsOfInterest: CGEventMask.max,
                                callback: callback, userInfo: nil) else {
    report("Event tap creation failed; nothing is blocked.\(lockOnFailure ? " Supervisor will request native locking." : "")")
    finishWorker(status: 1, teardown: {})
    exit(1)
}
let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)
// macOS may remove unsupported or unauthorized bits from the requested mask.
// Verify ordinary event-mask registration and report the actual mask for gesture trials.
var tapCount: UInt32 = 0
let countResult = CGGetEventTapList(0, nil, &tapCount)
var tapList = [CGEventTapInformation](repeating: CGEventTapInformation(), count: Int(tapCount) + 16)
var listed: UInt32 = 0
let listResult = CGGetEventTapList(UInt32(tapList.count), &tapList, &listed)
let own = tapList.prefix(min(Int(listed), tapList.count)).filter {
    $0.tappingProcess == getpid() && $0.tapPoint == .cgSessionEventTap
}
guard countResult == .success, listResult == .success, own.count == 1,
      own[0].enabled, own[0].eventsOfInterest & requiredOrdinaryMask == requiredOrdinaryMask,
      CGEvent.tapIsEnabled(tap: tap), !IsSecureEventInputEnabled() else {
    finishWorker(status: 1) {
        CGEvent.tapEnable(tap: tap, enable: false)
        CFMachPortInvalidate(tap)
        report("Ordinary event-mask registration could not be verified; filter removed.\(lockOnFailure ? " Supervisor will request native locking." : "")")
    }
    exit(1)
}
let registeredMask = own[0].eventsOfInterest
let start = ProcessInfo.processInfo.systemUptime
// Default SIGALRM terminates even if the run loop stalls. Process death removes its tap.
signal(SIGALRM, SIG_DFL)
alarm(seconds.map { UInt32($0 + 2) } ?? 0)
var overlay: PrivacyOverlay?
if privacy {
    overlay = PrivacyOverlay(instruction: mode == "lock"
        ? "Input Guard is active\nType your Input Guard code to release. No Enter needed."
        : "Input Guard trial\nInput is blocked. This trial ends automatically.", coverageLost: {
            stopReason = "display coverage lost"; exitStatus = 3; stopGuardLoop()
        })
    if overlay?.show() != true {
        finishWorker(status: 3) {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            overlay?.hide()
            report("Privacy overlay failed; filter removed.")
        }
        exit(3)
    }
}
let timer = Timer(timeInterval: 1, repeats: true) { _ in
    let elapsed = ProcessInfo.processInfo.systemUptime - start
    if IsSecureEventInputEnabled() || !CGEvent.tapIsEnabled(tap: tap)
        || (mode == "lock" && keyboardLayoutID() != initialLayout) {
        stopReason = "Secure Input, layout change or event tap disabled; protection lost"
        exitStatus = 3
        stopGuardLoop()
    } else if let seconds, elapsed >= Double(seconds) {
        normalCompletion = true
        stopGuardLoop()
    } else if let workerChannel, !workerChannel.heartbeat() {
        stopReason = "supervisor channel lost"; exitStatus = 3
        stopGuardLoop()
    } else if mode == "trial" {
        let remaining = seconds.map { "\($0 - Int(elapsed))s" } ?? "unlimited"
        report("ACTIVE tap_enabled=true remaining=\(remaining) captured=\(counts.values.reduce(0,+))")
    }
}
RunLoop.main.add(timer, forMode: .common)
let duration = seconds.map { "\($0)s" } ?? "unlimited"
report("\(blocking ? "BLOCKING" : "OBSERVING") pid=\(getpid()) duration=\(duration) tap_enabled=\(CGEvent.tapIsEnabled(tap: tap)) registered_mask=0x\(String(registeredMask, radix: 16)); \(unlimited ? "no automatic expiry" : "automatic expiry")")
if mode == "lock" {
    report("Type your code anywhere to release. No Enter needed.\(lockOnFailure ? " Terminating the guard requests native macOS locking." : " Emergency from another session: kill -TERM \(getpid())")")
}
if privacy { NSApplication.shared.run() } else { CFRunLoopRun() }
if !normalCompletion && exitStatus == 0 {
    stopReason = "event loop ended without authorized completion"; exitStatus = 3
}
// Replace the active-run backstop with a bounded cleanup window; a delayed
// completion ACK must not race the original timed-run alarm.
alarm(4)
if exitStatus == 0, let workerChannel, !workerChannel.complete() {
    stopReason = "supervisor did not acknowledge completion"; exitStatus = 3
}
finishWorker(status: exitStatus) {
    CGEvent.tapEnable(tap: tap, enable: false)
    CFMachPortInvalidate(tap)
    overlay?.hide()
    timer.invalidate()
    alarm(0)
    for (key, count) in (mode == "lock" ? [:] : counts).sorted(by: { $0.key < $1.key }) {
        let parts = key.split(separator: ":")
        let pid = Int32(parts[1]) ?? 0
        report("event_type=\(parts[0]) source_pid=\(pid) count=\(count) source=\(pid == 0 ? "hardware/system" : processPath(pid))")
    }
    for control in BrightnessControl.allCases {
        if let count = brightnessCounts[control] {
            report("brightness_control=\(control.rawValue) \(blocking ? "passed" : "eligible")_events=\(count)")
        }
    }
    report("ENDED reason=\(stopReason) elapsed=\(Int(ProcessInfo.processInfo.systemUptime - start))s; input filter removed")
}
withExtendedLifetime(blockingInstance) {}
exit(exitStatus)

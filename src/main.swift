// SPDX-License-Identifier: MIT
// Session event-tap foundation adapted from choiyounggi/mac-inputlock; see THIRD_PARTY_NOTICES.md.
// A session event filter, not a macOS authentication boundary.
import Foundation
import CoreGraphics
import ApplicationServices
import Carbon
import Darwin
import Security

let statusOutput = StatusOutput()
atexit { statusOutput.flush() }
func report(_ message: String) { statusOutput.report(message) }

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

let args = Array(CommandLine.arguments.dropFirst())
let mode = args.first ?? "help"
if mode == "--version" {
    report("input-guard 0.2.0")
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
    input-guard probe              Show permissions, Secure Input and keyboard layout.
    input-guard check-lock         Check that the macOS Lock Screen menu action is available.
    input-guard test-screen-lock   Request the real macOS lock screen (stops computer use).
    input-guard --version          Show the release version.

    Codes use 8...64 lowercase letters/digits (a-z, 0-9).
    To unlock, type that code anywhere without Shift/Caps Lock, then release the last key.
    No Enter is needed. Release all held keys/buttons to finish unlocking.
    Five incorrect complete candidates pause code entry for 30 seconds.
    Codes are never printed. Only set-code saves a code.
    Saved-code changes apply to future runs; an active guard keeps its current code.
    Supports Apple Norwegian, Norwegian Extended, US and ABC QWERTY layouts.
    Timed runs expire automatically; unlimited has no expiry. Process exit removes the filter.
    Detected protection loss or TERM/HUP/INT requests the macOS lock screen.
    This fallback is best effort; SIGKILL/crashes are not covered.
    This is an input guard, not the macOS security lock. Screen contents remain visible.
    """)
    exit(0)
}
if mode == "probe" {
    report("accessibility=\(AXIsProcessTrusted()) secure_input=\(IsSecureEventInputEnabled()) layout=\(keyboardLayoutID())")
    exit(0)
}
if mode == "check-lock" || mode == "test-screen-lock" {
    guard args.count == 1 else { report("This command accepts no arguments."); exit(2) }
    guard AXIsProcessTrusted() else { report("Accessibility permission is required. No lock requested."); exit(1) }
    if mode == "check-lock" {
        let available = ScreenLocker().available()
        report(available ? "Lock Screen menu action is available; no lock requested." : "Lock Screen menu action is unavailable; no lock requested.")
        exit(available ? 0 : 1)
    }
    switch ScreenLocker().request() {
    case .accepted: report("macOS lock request accepted; verify the login screen yourself."); exit(0)
    case .unavailable: report("Lock Screen menu action unavailable. Lock state is unconfirmed."); exit(3)
    case .rejected(let code): report("Lock request returned AX error \(code). Lock state is unconfirmed."); exit(3)
    }
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
guard ["observe", "trial", "lock"].contains(mode), args.count <= 2,
      unlimited || (seconds.map { (1...(mode == "lock" ? 28800 : 60)).contains($0) } ?? false) else {
    report("Invalid mode or duration. Run input-guard --help.")
    exit(2)
}
var blockingInstance: BlockingInstance?
if mode != "observe" {
    do { blockingInstance = try BlockingInstance(path: BlockingInstance.defaultPath()) }
    catch BlockingInstanceError.alreadyRunning { report("Another blocking instance is already running. Nothing changed."); exit(1) }
    catch { report("Unable to acquire the blocking-instance lock. Nothing is blocked."); exit(1) }
}
guard AXIsProcessTrusted() else {
    if mode == "lock" {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
    report("Accessibility permission required for this executable or its launching app (e.g. Terminal). Enable it in System Settings > Privacy & Security > Accessibility, then retry. Nothing is blocked.")
    exit(1)
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

// Recheck after potentially long Keychain/code prompts, before installing a tap.
guard AXIsProcessTrusted(), !IsSecureEventInputEnabled(),
      mode != "lock" || supportedLayouts.contains(keyboardLayoutID()) else {
    report("Permissions, Secure Input or keyboard layout changed before arming. Nothing is blocked.")
    exit(1)
}
if mode == "lock", !ScreenLocker().available() {
    report("Cannot find the macOS Lock Screen fallback. Nothing is blocked. Run input-guard check-lock.")
    exit(1)
}

var counts: [String: Int] = [:]
var captured: UInt64 = 0
var stopReason = "deadline"
var exitStatus: Int32 = 0
let blocking = mode != "observe"
let forbidden: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift, .maskAlphaShift, .maskSecondaryFn]
let heldModifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift, .maskSecondaryFn]
let modifierKeys: Set<Int64> = [54,55,56,57,58,59,60,61,62,63]
var decoder = UnlockSequence(code: mode == "lock" ? unlockCode : [0])
let eventTypes: [CGEventType] = [
    .keyDown, .keyUp, .flagsChanged, .leftMouseDown, .leftMouseUp,
    .rightMouseDown, .rightMouseUp, .mouseMoved, .leftMouseDragged,
    .rightMouseDragged, .scrollWheel, .otherMouseDown, .otherMouseUp, .otherMouseDragged
]
let mask = eventTypes.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
var currentTap: CFMachPort?
var failurePolicy = FailurePolicy()

@discardableResult
func finishOwnerUnlockIfReady() -> Bool {
    guard mode == "lock", decoder.readyToUnlock,
          !failurePolicy.defersCodeUnlock(now: ProcessInfo.processInfo.systemUptime) else { return false }
    stopReason = "unlock code accepted; all held inputs released"
    CFRunLoopStop(CFRunLoopGetMain())
    return true
}

func protectionLost(_ reason: String, explicitRequest: Bool = false) {
    guard mode == "lock" else {
        stopReason = reason; exitStatus = 3; CFRunLoopStop(CFRunLoopGetMain()); return
    }
    // Restore whatever interception is still possible before the slower AX request.
    // This does not undo exposure while the tap was disabled or bypass Secure Input.
    if let tap = currentTap, !CGEvent.tapIsEnabled(tap: tap) { CGEvent.tapEnable(tap: tap, enable: true) }
    exitStatus = 3; stopReason = reason
    guard failurePolicy.begin(now: ProcessInfo.processInfo.systemUptime, explicitRequest: explicitRequest) else { return }
    report("PROTECTION LOST: \(reason). Requesting macOS Lock Screen; computer use may stop.")
    DispatchQueue.global(qos: .userInitiated).async {
        let result = ScreenLocker().request()
        DispatchQueue.main.async {
            let accepted: Bool
            switch result {
            case .accepted:
                accepted = true
                report("macOS lock request accepted; lock state unconfirmed. Remaining filtering stays active until code unlock or timed expiry.")
            case .unavailable, .rejected:
                accepted = false
                report("LOCK UNCONFIRMED: fallback unavailable or failed; retaining remaining filtering and retrying persistent loss after 15 seconds. Use the normal macOS lock screen.")
            }
            failurePolicy.complete(accepted: accepted, now: ProcessInfo.processInfo.systemUptime)
            finishOwnerUnlockIfReady()
        }
    }
}

let callback: CGEventTapCallBack = { _, type, event, _ in
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        protectionLost("event tap disabled")
        return Unmanaged.passUnretained(event)
    }
    captured &+= 1
    let pid = event.getIntegerValueField(.eventSourceUnixProcessID)
    if mode != "lock" {
        let key = "\(type.rawValue):\(pid)"
        if counts[key] != nil || counts.count < 256 { counts[key, default: 0] += 1 }
    }
    if mode == "lock" {
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        let button = event.getIntegerValueField(.mouseEventButtonNumber)
        let input: GuardInput?
        switch type {
        case .keyDown: input = .keyDown(key, repeating: event.getIntegerValueField(.keyboardEventAutorepeat) != 0, forbiddenModifiers: !event.flags.intersection(forbidden).isEmpty)
        case .keyUp: input = .keyUp(key)
        case .flagsChanged: input = .modifiers(held: !event.flags.intersection(heldModifiers).isEmpty)
        case .leftMouseDown, .rightMouseDown, .otherMouseDown: input = .buttonDown(button)
        case .leftMouseUp, .rightMouseUp, .otherMouseUp: input = .buttonUp(button)
        default: input = nil
        }
        if let input {
            let result = decoder.consume(input, hardwareOrigin: pid == 0, now: ProcessInfo.processInfo.systemUptime)
            if result == .unlocked { finishOwnerUnlockIfReady() }
            else if result == .cooldownStarted { report("Code entry paused for 30 seconds after five incorrect candidates; input remains blocked.") }
        }
    }
    return blocking ? nil : Unmanaged.passUnretained(event)
}

var signalSources: [DispatchSourceSignal] = []
if mode == "lock" {
    for number in [SIGTERM, SIGHUP, SIGINT] {
        signal(number, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
        source.setEventHandler { protectionLost("termination signal \(number)", explicitRequest: true) }
        source.resume(); signalSources.append(source)
    }
}
guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                options: blocking ? .defaultTap : .listenOnly, eventsOfInterest: mask,
                                callback: callback, userInfo: nil) else {
    report("Event tap creation failed; nothing is blocked.")
    exit(1)
}
currentTap = tap
let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)
// A non-null tap may have silently lost requested event bits. Check actual registration.
var tapCount: UInt32 = 0
let countResult = CGGetEventTapList(0, nil, &tapCount)
var tapList = [CGEventTapInformation](repeating: CGEventTapInformation(), count: Int(tapCount) + 16)
var listed: UInt32 = 0
let listResult = CGGetEventTapList(UInt32(tapList.count), &tapList, &listed)
let own = tapList.prefix(min(Int(listed), tapList.count)).filter {
    $0.tappingProcess == getpid() && $0.tapPoint == .cgSessionEventTap
}
guard countResult == .success, listResult == .success, own.count == 1,
      own[0].eventsOfInterest & mask == mask, own[0].enabled,
      CGEvent.tapIsEnabled(tap: tap), AXIsProcessTrusted(), !IsSecureEventInputEnabled() else {
    CGEvent.tapEnable(tap: tap, enable: false)
    report("Requested event coverage could not be verified. Guard did not arm.")
    exit(1)
}
// Seed only after interception exists: releases racing with startup are queued.
let initiallyHeldKeys = Set((0..<128).map(Int64.init).filter {
    !modifierKeys.contains($0) && CGEventSource.keyState(.hidSystemState, key: CGKeyCode($0))
})
let initiallyHeldButtons = Set((0..<32).map(Int64.init).filter {
    CGEventSource.buttonState(.hidSystemState, button: CGMouseButton(rawValue: UInt32($0))!)
})
decoder = UnlockSequence(code: mode == "lock" ? unlockCode : [0], keys: initiallyHeldKeys,
    buttons: initiallyHeldButtons, modifiersHeld: !CGEventSource.flagsState(.hidSystemState).intersection(heldModifiers).isEmpty)
let start = ProcessInfo.processInfo.systemUptime
// Explicit timed runs still expire even if the run loop stalls. Unlimited has no expiry.
signal(SIGALRM, SIG_DFL)
alarm(seconds.map { UInt32($0 + 2) } ?? 0)
let timer = Timer(timeInterval: 1, repeats: true) { _ in
    let elapsed = ProcessInfo.processInfo.systemUptime - start
    if finishOwnerUnlockIfReady() { return }
    if !AXIsProcessTrusted() || IsSecureEventInputEnabled() || !CGEvent.tapIsEnabled(tap: tap)
        || (mode == "lock" && !supportedLayouts.contains(keyboardLayoutID())) {
        protectionLost("Secure Input, unsupported layout or event tap disabled")
    }
    if let seconds, elapsed >= Double(seconds) {
        stopReason = "deadline"; CFRunLoopStop(CFRunLoopGetMain())
    } else if mode == "trial" {
        report("ACTIVE tap_enabled=\(CGEvent.tapIsEnabled(tap: tap)) remaining=\(seconds! - Int(elapsed))s captured=\(captured)")
    }
}
RunLoop.main.add(timer, forMode: .common)
let duration = seconds.map { "\($0)s" } ?? "unlimited"
report("\(blocking ? "BLOCKING" : "OBSERVING") pid=\(getpid()) duration=\(duration) tap_enabled=true event_mask_verified=true; \(unlimited ? "no automatic expiry" : "automatic expiry")")
if mode == "lock" { report("Type your code and release all keys/buttons to unlock. SIGTERM requests macOS Lock Screen; SIGKILL releases without locking.") }
CFRunLoopRun()
CGEvent.tapEnable(tap: tap, enable: false)
timer.invalidate()
alarm(0)
for (key, count) in counts.sorted(by: { $0.key < $1.key }) {
    let parts = key.split(separator: ":")
    let pid = Int32(parts[1]) ?? 0
    report("event_type=\(parts[0]) source_pid=\(pid) count=\(count) source=\(pid == 0 ? "hardware/system" : processPath(pid))")
}
report("ENDED reason=\(stopReason) elapsed=\(Int(ProcessInfo.processInfo.systemUptime - start))s; input filter removed")
exit(exitStatus)

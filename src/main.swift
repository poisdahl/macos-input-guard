// SPDX-License-Identifier: MIT
// Session event-tap foundation adapted from choiyounggi/mac-inputlock; see THIRD_PARTY_NOTICES.md.
// A session event filter, not a macOS authentication boundary.
import Foundation
import CoreGraphics
import ApplicationServices
import Carbon
import Darwin
import Security

func report(_ message: String) {
    FileHandle.standardOutput.write(Data((message + "\n").utf8))
}

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

let args = Array(CommandLine.arguments.dropFirst())
let mode = args.first ?? "help"
if mode == "--version" {
    report("input-guard 0.1.0")
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
    input-guard --version          Show the release version.

    Codes use 8...64 lowercase letters/digits (a-z, 0-9).
    To unlock, type that code anywhere without Shift/Caps Lock, then release the last key.
    No Enter is needed. Codes are never printed. Only set-code saves a code.
    Saved-code changes apply to future runs; an active guard keeps its current code.
    Supports Apple Norwegian, Norwegian Extended, US and ABC QWERTY layouts.
    Timed runs expire automatically; unlimited has no expiry. Process exit removes the filter.
    This is an input guard, not the macOS security lock. Screen contents remain visible.
    """)
    exit(0)
}
if mode == "probe" {
    report("accessibility=\(AXIsProcessTrusted()) secure_input=\(IsSecureEventInputEnabled()) layout=\(keyboardLayoutID())")
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
guard ["observe", "trial", "lock"].contains(mode), args.count <= 2,
      unlimited || (seconds.map { (1...(mode == "lock" ? 28800 : 60)).contains($0) } ?? false) else {
    report("Invalid mode or duration. Run input-guard --help.")
    exit(2)
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

var counts: [String: Int] = [:]
var stopReason = "deadline"
var exitStatus: Int32 = 0
let blocking = mode != "observe"
var enteredCode: [UInt8] = []
var lastCodeKeyTime: TimeInterval = 0
var unlockingKey: Int64?
let eventTypes: [CGEventType] = [
    .keyDown, .keyUp, .flagsChanged, .leftMouseDown, .leftMouseUp,
    .rightMouseDown, .rightMouseUp, .mouseMoved, .leftMouseDragged,
    .rightMouseDragged, .scrollWheel, .otherMouseDown, .otherMouseUp, .otherMouseDragged
]
let mask = eventTypes.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
let callback: CGEventTapCallBack = { _, type, event, _ in
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        stopReason = "event tap disabled; protection lost"
        exitStatus = 3
        CFRunLoopStop(CFRunLoopGetMain())
        return Unmanaged.passUnretained(event)
    }
    let pid = event.getIntegerValueField(.eventSourceUnixProcessID)
    let key = "\(type.rawValue):\(pid)"
    counts[key, default: 0] += 1
    if mode == "lock", pid == 0 {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyUp, let finalKey = unlockingKey, keyCode == finalKey {
            stopReason = "unlock code accepted"
            CFRunLoopStop(CFRunLoopGetMain())
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
guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                options: blocking ? .defaultTap : .listenOnly, eventsOfInterest: mask,
                                callback: callback, userInfo: nil) else {
    report("Event tap creation failed; nothing is blocked.")
    exit(1)
}
let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)
let start = ProcessInfo.processInfo.systemUptime
// Default SIGALRM terminates even if the run loop stalls. Process death removes its tap.
signal(SIGALRM, SIG_DFL)
alarm(seconds.map { UInt32($0 + 2) } ?? 0)
let timer = Timer(timeInterval: 1, repeats: true) { _ in
    let elapsed = ProcessInfo.processInfo.systemUptime - start
    if IsSecureEventInputEnabled() || !CGEvent.tapIsEnabled(tap: tap)
        || (mode == "lock" && keyboardLayoutID() != initialLayout) {
        stopReason = "Secure Input, layout change or event tap disabled; protection lost"
        exitStatus = 3
        CFRunLoopStop(CFRunLoopGetMain())
    } else if let seconds, elapsed >= Double(seconds) {
        CFRunLoopStop(CFRunLoopGetMain())
    } else if blocking && (mode == "trial" || Int(elapsed) % 60 == 0) {
        let remaining = seconds.map { "\($0 - Int(elapsed))s" } ?? "unlimited"
        report("ACTIVE tap_enabled=true remaining=\(remaining) captured=\(counts.values.reduce(0,+))")
    }
}
RunLoop.main.add(timer, forMode: .common)
let duration = seconds.map { "\($0)s" } ?? "unlimited"
report("\(blocking ? "BLOCKING" : "OBSERVING") pid=\(getpid()) duration=\(duration) tap_enabled=\(CGEvent.tapIsEnabled(tap: tap)); \(unlimited ? "no automatic expiry" : "automatic expiry")")
if mode == "lock" { report("Type your code anywhere to release. No Enter needed. Emergency from another session: kill -TERM \(getpid())") }
CFRunLoopRun()
CGEvent.tapEnable(tap: tap, enable: false)
timer.invalidate()
alarm(0)
for (key, count) in (mode == "lock" ? [:] : counts).sorted(by: { $0.key < $1.key }) {
    let parts = key.split(separator: ":")
    let pid = Int32(parts[1]) ?? 0
    report("event_type=\(parts[0]) source_pid=\(pid) count=\(count) source=\(pid == 0 ? "hardware/system" : processPath(pid))")
}
report("ENDED reason=\(stopReason) elapsed=\(Int(ProcessInfo.processInfo.systemUptime - start))s; input filter removed")
exit(exitStatus)

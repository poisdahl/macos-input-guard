// SPDX-License-Identifier: MIT
import Foundation
import Darwin

// A slow/disconnected output consumer must never stall or kill the event tap.
// No file-status flags on the inherited terminal/pipe are changed.
final class StatusOutput {
    private let descriptor: Int32
    private let queue = DispatchQueue(label: "input-guard.status")
    private let slots = DispatchSemaphore(value: 32)
    private let pending = DispatchGroup()

    init(descriptor: Int32 = STDOUT_FILENO) {
        self.descriptor = descriptor
        signal(SIGPIPE, SIG_IGN)
    }

    func report(_ message: String) {
        guard slots.wait(timeout: .now()) == .success else { return }
        let data = Data((message + "\n").utf8.prefix(8192))
        pending.enter()
        queue.async { [self] in
            defer { slots.signal(); pending.leave() }
            data.withUnsafeBytes { bytes in
                var offset = 0
                while offset < bytes.count {
                    let count = Darwin.write(descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                    if count > 0 { offset += count }
                    else if count < 0 && errno == EINTR { continue }
                    else { break } // EPIPE and other output errors are nonfatal.
                }
            }
        }
    }

    func flush() {
        _ = pending.wait(timeout: .now() + .milliseconds(250))
    }
}

// SPDX-License-Identifier: MIT
import Foundation
import Darwin

enum BlockingInstanceError: Error { case unavailable, alreadyRunning }

final class BlockingInstance {
    private let descriptor: Int32

    static func defaultPath() throws -> String {
        var directory = [CChar](repeating: 0, count: Int(PATH_MAX))
        let count = confstr(_CS_DARWIN_USER_TEMP_DIR, &directory, directory.count)
        guard count > 0, count <= directory.count else { throw BlockingInstanceError.unavailable }
        return String(cString: directory) + "input-guard.blocking.lock"
    }

    init(path: String) throws {
        let opened = open(path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard opened >= 0 else { throw BlockingInstanceError.unavailable }
        var info = stat()
        guard fstat(opened, &info) == 0, info.st_uid == getuid(),
              info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1 else {
            close(opened); throw BlockingInstanceError.unavailable
        }
        guard flock(opened, LOCK_EX | LOCK_NB) == 0 else {
            let busy = errno == EWOULDBLOCK
            close(opened)
            throw busy ? BlockingInstanceError.alreadyRunning : BlockingInstanceError.unavailable
        }
        descriptor = opened
    }

    // Keep the inode in place: unlinking a held lock would permit a second holder.
    deinit { close(descriptor) }
}

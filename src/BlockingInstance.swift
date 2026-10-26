// SPDX-License-Identifier: MIT
import Foundation
import Darwin

enum BlockingInstanceError: Error { case unavailable, alreadyRunning }

final class BlockingInstance {
    private let descriptor: Int32
    var inheritedDescriptor: Int32 { descriptor }

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
        // Keep the source away from worker protocol/reservation descriptors 3/4.
        let inherited = fcntl(opened, F_DUPFD_CLOEXEC, 10)
        close(opened)
        guard inherited >= 0 else { throw BlockingInstanceError.unavailable }
        descriptor = inherited
    }

    init(inheritedDescriptor: Int32) throws {
        var info = stat()
        guard fstat(inheritedDescriptor, &info) == 0, info.st_uid == getuid(),
              info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1 else {
            throw BlockingInstanceError.unavailable
        }
        _ = fcntl(inheritedDescriptor, F_SETFD, FD_CLOEXEC)
        descriptor = inheritedDescriptor
    }

    // Keep the inode in place: unlinking a held lock would permit a second holder.
    deinit { close(descriptor) }
}

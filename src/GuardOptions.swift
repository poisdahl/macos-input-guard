// SPDX-License-Identifier: MIT

// Parse policy without permissions, Keychain access or process creation.
struct GuardOptions {
    enum Invalid: Error { case options }
    let arguments: [String]
    let args: [String]
    let mode: String
    let isSupervisedWorker: Bool
    let privacy: Bool
    let lockOnFailure: Bool

    init(arguments raw: [String]) throws {
        var supplied = raw
        isSupervisedWorker = supplied.first == "__worker"
        if isSupervisedWorker { supplied.removeFirst() }
        arguments = supplied
        let flags = ["--privacy", "--lock-on-failure", "--no-lock-on-failure"]
        args = supplied.filter { !flags.contains($0) }
        mode = args.first ?? "help"
        privacy = supplied.contains("--privacy")
        let enable = supplied.contains("--lock-on-failure")
        let disable = supplied.contains("--no-lock-on-failure")
        guard flags.allSatisfy({ flag in supplied.filter { $0 == flag }.count <= 1 }),
              !(enable && disable),
              (!privacy && !enable && !disable) || ["lock", "trial"].contains(mode),
              !isSupervisedWorker || (enable && !disable) else { throw Invalid.options }
        lockOnFailure = enable || (mode == "lock" && !disable)
    }

    // The internal worker must explicitly acknowledge supervision, even when
    // the owner used the default. It never starts another supervisor.
    var workerArguments: [String] {
        ["__worker"] + arguments.filter { $0 != "--lock-on-failure" } + ["--lock-on-failure"]
    }
}

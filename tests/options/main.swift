// SPDX-License-Identifier: MIT
// Pure option parsing: no event taps, processes, Keychain or native locks.
let locks = [["lock"], ["lock", "60"], ["lock", "unlimited"], ["lock", "--privacy"]]
for args in locks {
    let options = try! GuardOptions(arguments: args)
    precondition(options.lockOnFailure && !options.isSupervisedWorker)
    precondition(options.privacy == args.contains("--privacy"))
    let worker = try! GuardOptions(arguments: options.workerArguments)
    precondition(worker.isSupervisedWorker && worker.lockOnFailure)
    precondition(worker.args == options.args && worker.privacy == options.privacy)
    precondition(options.workerArguments.filter { $0 == "--lock-on-failure" }.count == 1)
}
for args in [["lock", "60", "--no-lock-on-failure"], ["trial"], ["trial", "--privacy"],
             ["trial", "--no-lock-on-failure"], ["observe"], ["preview"], ["probe"],
             ["set-code"], ["forget-code"], ["--version"], ["--help"], []] {
    precondition(!(try! GuardOptions(arguments: args)).lockOnFailure)
}
for args in [["lock", "--lock-on-failure"], ["trial", "--lock-on-failure"],
             ["__worker", "lock", "--lock-on-failure"], ["__worker", "trial", "--lock-on-failure"]] {
    let options = try! GuardOptions(arguments: args)
    precondition(options.lockOnFailure)
    precondition(options.workerArguments.filter { $0 == "--lock-on-failure" }.count == 1)
}
for args in [["lock", "--lock-on-failure", "--no-lock-on-failure"],
             ["lock", "--no-lock-on-failure", "--no-lock-on-failure"],
             ["trial", "--lock-on-failure", "--lock-on-failure"],
             ["lock", "--privacy", "--privacy"], ["probe", "--no-lock-on-failure"],
             ["__worker", "lock"], ["__worker", "lock", "--no-lock-on-failure"]] {
    do { _ = try GuardOptions(arguments: args); preconditionFailure("Accepted invalid options") }
    catch { }
}
print("PASS: lock fallback defaults, opt-out, safe trial defaults and explicit worker policy")

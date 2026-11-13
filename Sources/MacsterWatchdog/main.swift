// macster-watchdog: restores normal sleep if Macster goes away while it is keeping the Mac awake.
//
// Macster starts this helper right before it disables sleep and holds the only write end of the helper's stdin.
//
//   • Macster writes "disarm": it turned sleep back on itself. The helper exits without doing anything.
//   • stdin reaches end-of-file first: Macster crashed, was force quit, or was killed. The kernel closes its end of
//     the pipe no matter how it died, and the helper runs `sudo -n /usr/bin/pmset -a disablesleep 0`.
//   • The helper receives SIGTERM, SIGHUP or SIGINT (logout, shutdown): same as end-of-file.
//
// It waits in kevent(2), so it uses no CPU while it waits. It never runs as root; the restore goes through the same
// two-command sudo rule the app uses. Once it's listening, it prints "armed" on stdout.

import Darwin
import os

// First, before anything else can take time: signals are ignored so they can't kill the process; kqueue still
// reports them below.
private let watchedSignals = [SIGTERM, SIGHUP, SIGINT]
for signalNumber in watchedSignals {
    signal(signalNumber, SIG_IGN)
}
signal(SIGPIPE, SIG_IGN)

private let log = Logger(subsystem: "io.github.macster", category: "watchdog")
private let disarmMessage = Array("disarm".utf8) // WatchdogProtocol.disarm in MacsterCore

private func restoreCommand() -> [String] {
    #if DEBUG
    // Lets the tests observe the restore without changing the machine's sleep settings.
    if let test = getenv("MACSTER_WATCHDOG_TEST_COMMAND") {
        return ["/bin/sh", "-c", String(cString: test)]
    }
    #endif
    return ["/usr/bin/sudo", "-n", "/usr/bin/pmset", "-a", "disablesleep", "0"]
}

private func restoreSleepAndExit(_ reason: String) -> Never {
    log.notice("Restoring normal sleep: \(reason, privacy: .public)")
    let status = spawnAndWait(restoreCommand())
    if status != 0 {
        log.error("Restoring normal sleep failed with status \(status, privacy: .public)")
    }
    exit(status == 0 ? 0 : 1)
}

/// Runs `command` with stdio on /dev/null and returns its exit status.
private func spawnAndWait(_ command: [String]) -> Int32 {
    var actions: posix_spawn_file_actions_t?
    posix_spawn_file_actions_init(&actions)
    defer { posix_spawn_file_actions_destroy(&actions) }
    posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
    posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, "/dev/null", O_WRONLY, 0)
    posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0)

    let arguments = command.map { strdup($0) } + [nil]
    let environment = [strdup("PATH=/usr/bin:/bin:/usr/sbin:/sbin"), nil]
    defer {
        arguments.forEach { free($0) }
        environment.forEach { free($0) }
    }

    var pid: pid_t = 0
    let spawnError = posix_spawn(&pid, command[0], &actions, nil, arguments, environment)
    guard spawnError == 0 else { return spawnError }

    var status: Int32 = 0
    while waitpid(pid, &status, 0) == -1 {
        guard errno == EINTR else { return -1 }
    }
    // WIFEXITED and WEXITSTATUS are macros Swift doesn't import.
    let signal = status & 0x7f
    return signal == 0 ? (status >> 8) & 0xff : 128 + signal
}

private func contains(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
    guard haystack.count >= needle.count else { return false }
    return (0...(haystack.count - needle.count)).contains { start in
        haystack[start..<(start + needle.count)].elementsEqual(needle)
    }
}

let queue = kqueue()
guard queue >= 0 else { restoreSleepAndExit("kqueue failed (errno \(errno))") }

var changes = [kevent(ident: UInt(STDIN_FILENO), filter: Int16(EVFILT_READ), flags: UInt16(EV_ADD), fflags: 0, data: 0, udata: nil)]
for signalNumber in watchedSignals {
    changes.append(kevent(ident: UInt(signalNumber), filter: Int16(EVFILT_SIGNAL), flags: UInt16(EV_ADD), fflags: 0, data: 0, udata: nil))
}
guard kevent(queue, changes, Int32(changes.count), nil, 0, nil) == 0 else {
    restoreSleepAndExit("kevent registration failed (errno \(errno))")
}

log.info("Armed")
_ = write(STDOUT_FILENO, "armed\n", 6)
var received: [UInt8] = []
var buffer = [UInt8](repeating: 0, count: 64)

while true {
    var event = kevent()
    let count = kevent(queue, nil, 0, &event, 1, nil)
    if count < 0 {
        if errno == EINTR { continue }
        restoreSleepAndExit("kevent failed (errno \(errno))")
    }
    guard count > 0 else { continue }

    if event.filter == Int16(EVFILT_SIGNAL) {
        restoreSleepAndExit("received signal \(event.ident)")
    }

    let bytesRead = read(STDIN_FILENO, &buffer, buffer.count)
    if bytesRead == 0 {
        restoreSleepAndExit("Macster exited without turning sleep back on")
    }
    if bytesRead < 0 {
        if errno == EINTR || errno == EAGAIN { continue }
        restoreSleepAndExit("reading from Macster failed (errno \(errno))")
    }

    received += buffer[..<bytesRead]
    if contains(received, disarmMessage) {
        log.info("Disarmed")
        exit(0)
    }
    received = Array(received.suffix(disarmMessage.count))
}

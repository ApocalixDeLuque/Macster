import Foundation
import MacsterCore
import os

/// A small helper process that stays alive while Macster keeps the Mac awake.
///
/// Macster holds the only write end of the helper's stdin. If Macster exits for any reason without disarming it —
/// a crash, a force quit, a logout — the helper reads end-of-file and turns normal sleep back on by itself. See
/// `Sources/MacsterWatchdog/main.swift`.
final class Watchdog {
    private let process: Process
    private let input: FileHandle
    private var isDisarmed = false
    private static let log = Logger(subsystem: "io.github.macster", category: "watchdog")

    private init(process: Process, input: FileHandle) {
        self.process = process
        self.input = input
    }

    /// Starts the helper. `onUnexpectedExit` runs on the main actor if it exits before `disarm()`.
    static func arm(onUnexpectedExit: @escaping @MainActor () -> Void) throws -> Watchdog {
        guard let url = helperURL else {
            throw SleepControlError.watchdogUnavailable("Its helper is missing from the app. Reinstall Macster.")
        }

        let pipe = Pipe()
        // No other child process may inherit the write end; otherwise the helper wouldn't see end-of-file when
        // Macster dies while that child is still running.
        _ = fcntl(pipe.fileHandleForWriting.fileDescriptor, F_SETFD, FD_CLOEXEC)

        let process = Process()
        process.executableURL = url
        process.standardInput = pipe
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        let watchdog = Watchdog(process: process, input: pipe.fileHandleForWriting)
        process.terminationHandler = { [weak watchdog] _ in
            Task { @MainActor in
                guard let watchdog, !watchdog.isDisarmed else { return }
                log.error("Watchdog exited while armed")
                onUnexpectedExit()
            }
        }

        do {
            try process.run()
        } catch {
            throw SleepControlError.watchdogUnavailable(error.localizedDescription)
        }
        log.info("Armed watchdog (pid \(process.processIdentifier, privacy: .public))")
        return watchdog
    }

    /// Lets the helper exit without touching sleep settings. Call after sleep is back on.
    func disarm() {
        guard !isDisarmed else { return }
        isDisarmed = true
        // SIGPIPE is ignored app-wide, so writing to a helper that already exited just fails quietly.
        try? input.write(contentsOf: Data(WatchdogProtocol.disarm.utf8))
        try? input.close()
    }

    /// Next to the app's executable: `Contents/MacOS` in the bundle, or the build folder during development.
    private static var helperURL: URL? {
        let candidates = [
            Bundle.main.url(forAuxiliaryExecutable: WatchdogProtocol.executableName),
            Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent(WatchdogProtocol.executableName),
        ]
        return candidates.compactMap { $0 }.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}

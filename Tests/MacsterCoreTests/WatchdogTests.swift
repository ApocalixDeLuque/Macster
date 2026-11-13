import Foundation
import Testing

/// Runs the real `macster-watchdog` from the debug build. Debug builds read `MACSTER_WATCHDOG_TEST_COMMAND`, so the
/// tests can see the restore happen without touching this Mac's sleep settings. `scripts/test.sh` builds it first.
private let watchdogBinary = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent(".build/debug/macster-watchdog")

@Suite(.enabled(if: FileManager.default.isExecutableFile(atPath: watchdogBinary.path), "run `swift build` first"))
struct WatchdogTests {

    private let marker = FileManager.default.temporaryDirectory.appendingPathComponent("macster-watchdog-\(UUID().uuidString)")

    @Test func `disarming exits without restoring`() async throws {
        let (process, input) = try launch()
        try input.write(contentsOf: Data("disarm\n".utf8))
        try input.close()
        let status = await exitStatus(of: process)
        #expect(status == 0)
        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }

    @Test func `restores when Macster goes away`() async throws {
        let (process, input) = try launch()
        try input.close() // What the kernel does when Macster crashes or is force quit.
        let status = await exitStatus(of: process)
        #expect(status == 0)
        #expect(FileManager.default.fileExists(atPath: marker.path))
        try? FileManager.default.removeItem(at: marker)
    }

    @Test func `restores on SIGTERM`() async throws {
        let (process, input) = try launch()
        try await waitUntilArmed()
        process.terminate()
        let status = await exitStatus(of: process)
        try? input.close()
        #expect(status == 0)
        #expect(FileManager.default.fileExists(atPath: marker.path))
        try? FileManager.default.removeItem(at: marker)
    }

    @Test func `other input doesn't disarm it`() async throws {
        let (process, input) = try launch()
        try input.write(contentsOf: Data("dis".utf8))
        try await Task.sleep(for: .milliseconds(100))
        try input.write(contentsOf: Data("ARM\n".utf8))
        try input.close()
        _ = await exitStatus(of: process)
        #expect(FileManager.default.fileExists(atPath: marker.path))
        try? FileManager.default.removeItem(at: marker)
    }

    @Test func `the disarm message can arrive in pieces`() async throws {
        let (process, input) = try launch()
        for piece in ["di", "sa", "rm\n"] {
            try input.write(contentsOf: Data(piece.utf8))
            try await Task.sleep(for: .milliseconds(50))
        }
        try input.close()
        #expect(await exitStatus(of: process) == 0)
        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }

    private func launch() throws -> (Process, FileHandle) {
        let process = Process()
        process.executableURL = watchdogBinary
        var environment = ProcessInfo.processInfo.environment
        environment["MACSTER_WATCHDOG_TEST_COMMAND"] = "/usr/bin/touch '\(marker.path)'"
        process.environment = environment
        let pipe = Pipe()
        process.standardInput = pipe
        process.standardOutput = output
        try process.run()
        return (process, pipe.fileHandleForWriting)
    }

    private let output = Pipe()

    /// The watchdog prints "armed" once its signal and stdin handling are in place.
    private func waitUntilArmed() async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(5)
        var received = ""
        while !received.contains("armed") {
            guard clock.now < deadline else { Issue.record("watchdog never reported armed"); return }
            // availableData returns as soon as anything arrives; read(upToCount:) on a pipe waits for the full count.
            let data = output.fileHandleForReading.availableData
            guard !data.isEmpty else { Issue.record("watchdog closed stdout before reporting armed"); return }
            received += String(decoding: data, as: UTF8.self)
        }
    }

    private func exitStatus(of process: Process) async -> Int32 {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(5)
        while process.isRunning, clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        return process.isRunning ? -1 : process.terminationStatus
    }
}

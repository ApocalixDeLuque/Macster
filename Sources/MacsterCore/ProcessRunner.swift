import Foundation

public struct ProcessOutput: Equatable, Sendable {
    public var status: Int32
    public var stdout: String
    public var stderr: String
    public var timedOut: Bool

    public var succeeded: Bool { status == 0 && !timedOut }
}

/// Runs short-lived programs without blocking a thread while they work.
public enum ProcessRunner {
    /// Runs `executable` to completion. Both output pipes are drained while it runs, so a program that writes a lot
    /// can't fill a pipe and deadlock. After `timeout` the program is sent SIGTERM and `timedOut` is set.
    public static func run(
        _ executable: String,
        _ arguments: [String] = [],
        timeout: Duration = .seconds(30)
    ) async throws -> ProcessOutput {
        let job = Job(executable: executable, arguments: arguments)
        return try await withCheckedThrowingContinuation { continuation in
            job.start(timeout: timeout) { continuation.resume(with: $0) }
        }
    }
}

/// Owns one `Process` and its pipes. `Process` isn't `Sendable`, so everything that touches it stays inside this
/// class; `lock` guards the state shared with the threads that read the pipes.
private final class Job: @unchecked Sendable {
    private let process = Process()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private let lock = NSLock()
    private var stdoutData = Data()
    private var stderrData = Data()
    private var timedOut = false

    init(executable: String, arguments: [String]) {
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
    }

    func start(timeout: Duration, completion: @escaping @Sendable (Result<ProcessOutput, any Error>) -> Void) {
        let finished = DispatchGroup()
        finished.enter()
        process.terminationHandler = { _ in finished.leave() }
        do {
            try process.run()
        } catch {
            completion(.failure(error))
            return
        }

        finished.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            let data = self.stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            self.lock.withLock { self.stdoutData = data }
            finished.leave()
        }
        finished.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            let data = self.stderrPipe.fileHandleForReading.readDataToEndOfFile()
            self.lock.withLock { self.stderrData = data }
            finished.leave()
        }

        let deadline = DispatchWorkItem {
            guard self.process.isRunning else { return }
            self.lock.withLock { self.timedOut = true }
            self.process.terminate()
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout.seconds, execute: deadline)

        finished.notify(queue: .global(qos: .userInitiated)) {
            deadline.cancel()
            let output = self.lock.withLock {
                ProcessOutput(
                    status: self.process.terminationStatus,
                    stdout: String(decoding: self.stdoutData, as: UTF8.self),
                    stderr: String(decoding: self.stderrData, as: UTF8.self),
                    timedOut: self.timedOut
                )
            }
            completion(.success(output))
        }
    }
}

extension Duration {
    var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}

import Foundation

/// Result of running an out-of-process command.
struct CommandOutput: Sendable {
    let standardOutput: String
    let standardError: String
    let exitCode: Int32

    var succeeded: Bool { exitCode == 0 }
}

enum CommandError: Error, Sendable {
    /// The executable is absent or not executable — expected on stripped systems.
    case executableUnavailable(path: String)
    case launchFailed(path: String, reason: String)
    /// The command overran its budget and was terminated.
    case timedOut(path: String, seconds: Double)
}

/// Abstraction over subprocess execution so discovery components can be tested
/// without touching the real system.
protocol CommandRunning: Sendable {
    func run(_ executable: String, arguments: [String], timeout: Duration) async throws -> CommandOutput
}

extension CommandRunning {
    func run(_ executable: String, arguments: [String]) async throws -> CommandOutput {
        try await run(executable, arguments: arguments, timeout: .seconds(5))
    }
}

/// `Process`-backed runner.
///
/// Both pipes are drained on dedicated queues while the child runs: reading them
/// sequentially would deadlock as soon as either exceeds the pipe buffer.
struct Shell: CommandRunning {
    func run(_ executable: String, arguments: [String], timeout: Duration) async throws -> CommandOutput {
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw CommandError.executableUnavailable(path: executable)
        }

        let seconds = Double(timeout.components.seconds)
            + Double(timeout.components.attoseconds) / 1e18

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let output = try Self.execute(executable, arguments, timeoutSeconds: seconds)
                    continuation.resume(returning: output)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func execute(
        _ executable: String,
        _ arguments: [String],
        timeoutSeconds: Double
    ) throws -> CommandOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            throw CommandError.launchFailed(path: executable, reason: error.localizedDescription)
        }

        let collector = OutputCollector()
        let group = DispatchGroup()
        for (pipe, isStandardOutput) in [(outPipe, true), (errPipe, false)] {
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                defer { group.leave() }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                collector.append(data, toStandardOutput: isStandardOutput)
            }
        }

        let watchdog = DispatchWorkItem {
            if process.isRunning {
                collector.markTimedOut()
                process.terminate()
            }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeoutSeconds, execute: watchdog)

        process.waitUntilExit()
        watchdog.cancel()
        group.wait()

        if collector.didTimeOut {
            throw CommandError.timedOut(path: executable, seconds: timeoutSeconds)
        }

        return CommandOutput(
            standardOutput: collector.standardOutputString,
            standardError: collector.standardErrorString,
            exitCode: process.terminationStatus
        )
    }
}

/// Serialises the two pipe-reading queues and the watchdog.
private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var outputData = Data()
    private var errorData = Data()
    private var timedOut = false

    func append(_ data: Data, toStandardOutput: Bool) {
        lock.lock()
        defer { lock.unlock() }
        if toStandardOutput { outputData.append(data) } else { errorData.append(data) }
    }

    func markTimedOut() {
        lock.lock()
        defer { lock.unlock() }
        timedOut = true
    }

    var didTimeOut: Bool {
        lock.lock()
        defer { lock.unlock() }
        return timedOut
    }

    var standardOutputString: String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: outputData, as: UTF8.self)
    }

    var standardErrorString: String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: errorData, as: UTF8.self)
    }
}

import Foundation
import OSLog

/// A process Localhost HQ started, with its pipes attached.
struct LaunchedProcess: Sendable {
    let pid: Int32
    let descriptor: LaunchDescriptor
    let startedAt: Date
}

enum LaunchError: Error, Sendable {
    case executableMissing(String)
    case workingDirectoryMissing(String)
    case launchFailed(String)

    var explanation: String {
        switch self {
        case .executableMissing(let path):
            "The launch command could not be found at \(path)."
        case .workingDirectoryMissing(let path):
            "The project directory \(path) no longer exists."
        case .launchFailed(let reason):
            "The service could not be started: \(reason)"
        }
    }
}

/// Launches processes and streams their output.
///
/// This is the *only* way Localhost HQ obtains logs. macOS provides no
/// mechanism to attach to the stdout of a process started elsewhere, so a
/// service adopted from a terminal has no live output until it is restarted
/// through the app. The product says so rather than pretending otherwise.
///
/// Output is delivered in batches, one per pipe read, so a burst of thousands
/// of lines costs a handful of UI updates rather than thousands.
actor ProcessLauncher {

    /// Retains launched processes; releasing a `Process` detaches its pipes.
    private var running: [Int32: Process] = [:]
    private let logger = Logger(subsystem: AppInfo.subsystem, category: "Launcher")

    /// Starts a process and streams its output.
    ///
    /// - Parameters:
    ///   - onOutput: called with a batch of complete lines and their stream.
    ///   - onExit: called once with the exit status.
    func launch(
        _ descriptor: LaunchDescriptor,
        onOutput: @escaping @Sendable ([String], LogStream) -> Void,
        onExit: @escaping @Sendable (Int32) -> Void
    ) throws -> LaunchedProcess {
        let executablePath = descriptor.executableURL.path
        guard FileManager.default.isExecutableFile(atPath: executablePath) else {
            throw LaunchError.executableMissing(executablePath)
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: descriptor.workingDirectory.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw LaunchError.workingDirectoryMissing(descriptor.workingDirectory.path)
        }

        let process = Process()
        // Executable and arguments are set separately: the command is never
        // assembled into a shell string, so nothing here can be injected.
        process.executableURL = descriptor.executableURL
        process.arguments = descriptor.arguments
        process.currentDirectoryURL = descriptor.workingDirectory
        process.standardInput = FileHandle.nullDevice

        // The child's environment is Localhost HQ's, plus a marker. The
        // original process's environment is not recoverable (see
        // LaunchDescriptor).
        var environment = ProcessInfo.processInfo.environment
        environment["LOCALHOST_HQ"] = "1"
        process.environment = environment

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        attach(outPipe, stream: .stdout, onOutput: onOutput)
        attach(errPipe, stream: .stderr, onOutput: onOutput)

        process.terminationHandler = { finished in
            // Detach handlers so the pipes can close and the object deallocate.
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            onExit(finished.terminationStatus)
        }

        do {
            try process.run()
        } catch {
            throw LaunchError.launchFailed(error.localizedDescription)
        }

        let pid = process.processIdentifier
        running[pid] = process
        logger.info("launched pid \(pid): \(descriptor.displayCommand, privacy: .public)")

        return LaunchedProcess(pid: pid, descriptor: descriptor, startedAt: Date())
    }

    /// Stops retaining a process once it has exited.
    func release(pid: Int32) {
        running.removeValue(forKey: pid)
    }

    func isTracking(pid: Int32) -> Bool { running[pid] != nil }

    /// Terminates everything we launched. Called when the app quits so dev
    /// servers are not orphaned without their logs.
    func terminateAll() {
        for (_, process) in running where process.isRunning {
            process.terminate()
        }
        running.removeAll()
    }

    // MARK: - Pipe plumbing

    private func attach(
        _ pipe: Pipe,
        stream: LogStream,
        onOutput: @escaping @Sendable ([String], LogStream) -> Void
    ) {
        // Pipe reads land on an arbitrary queue and can split mid-line, so the
        // tail is carried forward until its newline arrives.
        let assembler = LineAssembler()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                let tail = assembler.flush()
                if !tail.isEmpty { onOutput(tail, stream) }
                handle.readabilityHandler = nil
                return
            }
            let lines = assembler.consume(data)
            if !lines.isEmpty { onOutput(lines, stream) }
        }
    }
}

/// Splits a byte stream into complete lines, holding any partial trailing line.
private final class LineAssembler: @unchecked Sendable {
    private let lock = NSLock()
    private var remainder = Data()

    /// Guards against a process emitting an unbounded line with no newline.
    private static let maximumLineBytes = 1 << 20

    func consume(_ data: Data) -> [String] {
        lock.lock()
        defer { lock.unlock() }

        remainder.append(data)
        var lines: [String] = []

        while let newline = remainder.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = remainder[remainder.startIndex..<newline]
            remainder.removeSubrange(remainder.startIndex...newline)
            lines.append(Self.decode(lineData))
        }

        if remainder.count > Self.maximumLineBytes {
            lines.append(Self.decode(remainder))
            remainder.removeAll(keepingCapacity: true)
        }
        return lines
    }

    func flush() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        guard !remainder.isEmpty else { return [] }
        let line = Self.decode(remainder)
        remainder.removeAll(keepingCapacity: true)
        return [line]
    }

    /// Dev-server output carries ANSI colour codes; they would render as noise.
    private static func decode(_ data: Data) -> String {
        let text = String(decoding: data, as: UTF8.self)
        return text
            .replacingOccurrences(of: "\r", with: "")
            .strippingANSIEscapes()
    }
}

extension String {
    /// Removes CSI/OSC escape sequences.
    func strippingANSIEscapes() -> String {
        guard contains("\u{1B}") else { return self }

        var result = ""
        result.reserveCapacity(count)
        var iterator = makeIterator()

        while let character = iterator.next() {
            guard character == "\u{1B}" else {
                result.append(character)
                continue
            }
            // Consume the introducer and everything up to the terminator.
            guard let next = iterator.next() else { break }
            if next == "[" {
                while let byte = iterator.next(), !("@"..."~" ~= byte) { continue }
            } else if next == "]" {
                // OSC runs to BEL or ST.
                while let byte = iterator.next() {
                    if byte == "\u{07}" { break }
                    if byte == "\u{1B}" { _ = iterator.next(); break }
                }
            }
        }
        return result
    }
}

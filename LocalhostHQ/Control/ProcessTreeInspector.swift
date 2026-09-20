import Darwin
import Foundation

/// A node in a process tree, for display.
struct ProcessNode: Sendable, Hashable, Identifiable {
    let pid: Int32
    let parentPID: Int32
    let name: String
    /// Set when this process is the one holding the listening socket.
    let listeningPort: Int?
    let children: [ProcessNode]

    var id: Int32 { pid }

    /// Depth-first flattening, for a simple indented list.
    func flattened(depth: Int = 0) -> [(node: ProcessNode, depth: Int)] {
        [(self, depth)] + children.flatMap { $0.flattened(depth: depth + 1) }
    }
}

/// The set of processes an operation may signal, and why.
struct ControlRoot: Sendable, Hashable {
    /// Topmost process belonging to the service.
    let pid: Int32
    let name: String
    /// Every process in the root's subtree, root first. Exactly what gets
    /// signalled — nothing outside this list is ever touched.
    let memberPIDs: [Int32]
    /// Human-readable justification, surfaced in the debug panel.
    let reason: String
}

/// Builds process trees and decides how much of one is safe to control.
///
/// The hard problem is that a dev server is rarely one process:
///
/// ```
/// zsh            ← the terminal you typed in. Must never be signalled.
/// └── pnpm       ← part of the job
///     └── node
///         └── next-server  :3000
/// ```
///
/// The boundary used is the **process group**. Shells with job control put each
/// job in its own group, so the interactive shell is never in its child job's
/// group, while a wrapper script legitimately is. Two further guards make that
/// safe in the cases where job control is absent: an ancestor is never adopted
/// if it is a session leader (a login or interactive shell always is), and
/// never if it is one of a small set of processes that cannot belong to a dev
/// server.
struct ProcessTreeInspector: Sendable {

    /// Names that must never be adopted as a control root, whatever the
    /// process group says.
    static let neverControl: Set<String> = [
        "launchd", "login", "sshd", "tmux", "screen", "sudo", "su",
        "Terminal", "iTerm2", "Warp", "WarpTerminal", "kitty", "alacritty", "Hyper",
        "Code Helper", "Electron", "LocalhostHQ",
    ]

    private let table: ProcessTableReading

    init(table: ProcessTableReading = SystemProcessTable()) {
        self.table = table
    }

    // MARK: - Trees

    /// Tree rooted at `pid`, built from a table snapshot.
    func tree(
        rootedAt pid: Int32,
        in entries: [ProcessTableEntry],
        listeningPorts: [Int32: Int] = [:]
    ) -> ProcessNode? {
        guard let root = entries.first(where: { $0.pid == pid }) else { return nil }

        var childrenByParent: [Int32: [ProcessTableEntry]] = [:]
        for entry in entries where entry.pid != entry.parentPID {
            childrenByParent[entry.parentPID, default: []].append(entry)
        }

        // Depth-limited: the table is a graph only in pathological cases, but a
        // cycle must not hang the UI.
        func build(_ entry: ProcessTableEntry, depth: Int, seen: Set<Int32>) -> ProcessNode {
            var seen = seen
            seen.insert(entry.pid)
            let children = depth >= 12 ? [] : (childrenByParent[entry.pid] ?? [])
                .filter { !seen.contains($0.pid) }
                .sorted { $0.pid < $1.pid }
                .map { build($0, depth: depth + 1, seen: seen) }

            return ProcessNode(
                pid: entry.pid,
                parentPID: entry.parentPID,
                name: entry.name,
                listeningPort: listeningPorts[entry.pid],
                children: children
            )
        }

        return build(root, depth: 0, seen: [])
    }

    /// Ancestors of `pid`, nearest parent first, stopping at pid 1.
    func ancestors(of pid: Int32, in entries: [ProcessTableEntry]) -> [ProcessTableEntry] {
        let byPID = Dictionary(entries.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })

        var result: [ProcessTableEntry] = []
        var seen: Set<Int32> = [pid]
        var cursor = byPID[pid]?.parentPID

        while let current = cursor, current > 1, !seen.contains(current), result.count < 24 {
            guard let entry = byPID[current] else { break }
            result.append(entry)
            seen.insert(current)
            cursor = entry.parentPID
        }
        return result
    }

    /// Descendants of `pid` including itself, root first.
    func subtreePIDs(of pid: Int32, in entries: [ProcessTableEntry]) -> [Int32] {
        var childrenByParent: [Int32: [ProcessTableEntry]] = [:]
        for entry in entries where entry.pid != entry.parentPID {
            childrenByParent[entry.parentPID, default: []].append(entry)
        }

        var result: [Int32] = []
        var queue: [Int32] = [pid]
        var seen: Set<Int32> = []

        while let current = queue.first {
            queue.removeFirst()
            guard seen.insert(current).inserted else { continue }
            result.append(current)
            queue.append(contentsOf: (childrenByParent[current] ?? []).map(\.pid))
        }
        return result
    }

    // MARK: - Control root

    /// Chooses the topmost process safe to signal on the service's behalf.
    ///
    /// Returns `nil` when the service process itself is not ours to signal.
    func controlRoot(
        for pid: Int32,
        in entries: [ProcessTableEntry],
        currentUserID: uid_t = getuid()
    ) -> ControlRoot? {
        guard let service = entries.first(where: { $0.pid == pid }) else { return nil }
        // Never signal another user's process: it needs root, which the app
        // deliberately never asks for.
        guard service.userID == currentUserID else { return nil }
        guard !Self.neverControl.contains(service.name) else { return nil }

        var root = service
        var reason = "the process holding the listening socket"

        for ancestor in ancestors(of: pid, in: entries) {
            guard isAdoptable(ancestor, jobGroupID: service.groupID, currentUserID: currentUserID) else { break }
            root = ancestor
            reason = "\(ancestor.name) is the job's parent, in the same process group"
        }

        return ControlRoot(
            pid: root.pid,
            name: root.name,
            // Only ever our own processes, even inside the subtree.
            memberPIDs: subtreePIDs(of: root.pid, in: entries).filter { candidate in
                entries.first(where: { $0.pid == candidate })?.userID == currentUserID
            },
            reason: reason
        )
    }

    /// Whether an ancestor belongs to the same launched job.
    private func isAdoptable(
        _ candidate: ProcessTableEntry,
        jobGroupID: Int32,
        currentUserID: uid_t
    ) -> Bool {
        guard candidate.pid > 1 else { return false }
        guard candidate.userID == currentUserID else { return false }
        // The job boundary. An interactive shell is in its own group, so this
        // single test excludes it.
        guard candidate.groupID == jobGroupID else { return false }
        guard !Self.neverControl.contains(candidate.name) else { return false }
        // Belt and braces for shells started without job control: a login or
        // interactive shell is always its session's leader.
        guard table.sessionID(of: candidate.pid) != candidate.pid else { return false }
        return true
    }
}

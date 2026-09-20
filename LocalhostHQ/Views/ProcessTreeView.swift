import SwiftUI

/// Indented process tree for the service inspector.
///
/// Shows what a stop would actually affect: processes inside the control root
/// are marked, so the blast radius of an action is visible before taking it.
struct ProcessTreeView: View {
    let root: ProcessNode
    let controlRootPID: Int32?
    let controlledPIDs: Set<Int32>

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(root.flattened(), id: \.node.pid) { item in
                row(item.node, depth: item.depth)
            }
        }
    }

    private func row(_ node: ProcessNode, depth: Int) -> some View {
        HStack(spacing: 6) {
            if depth > 0 {
                Text(String(repeating: "   ", count: depth - 1) + "└")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary.opacity(0.6))
            }

            Text(node.name)
                .font(.system(size: 11, weight: node.pid == controlRootPID ? .semibold : .regular))
                .foregroundStyle(controlledPIDs.contains(node.pid) ? Theme.textPrimary : Theme.textTertiary)

            Text(String(node.pid))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.textTertiary)

            if let port = node.listeningPort {
                PortBadge(port: port, isProminent: true)
            }

            if node.pid == controlRootPID {
                StatePill(text: "control root", color: Theme.accent)
            }

            Spacer(minLength: 0)
        }
    }
}

#Preview {
    ProcessTreeView(
        root: ProcessNode(
            pid: 4_810, parentPID: 1, name: "pnpm", listeningPort: nil,
            children: [
                ProcessNode(
                    pid: 4_811, parentPID: 4_810, name: "node", listeningPort: nil,
                    children: [
                        ProcessNode(pid: 4_812, parentPID: 4_811, name: "next-server", listeningPort: 3_000, children: []),
                    ]
                ),
            ]
        ),
        controlRootPID: 4_810,
        controlledPIDs: [4_810, 4_811, 4_812]
    )
    .padding(16)
    .frame(width: 340)
    .background(Theme.canvas)
    .preferredColorScheme(.dark)
}

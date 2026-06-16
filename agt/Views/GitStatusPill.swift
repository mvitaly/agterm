import agtCore
import SwiftUI

/// The detail-pane title-bar git pill: a branch glyph plus the branch name (or
/// `detached @ <shortsha>`), `↑N ↓N` when nonzero, a worktree chip for a linked
/// worktree, and a dimmed `*N` dirty marker when there are uncommitted changes.
/// Sits in the window toolbar's primary-action slot.
///
/// A `nil` status (the cwd is not a git work tree) renders nothing — no pill at
/// all, so the title bar is just the session name.
struct GitStatusPill: View {
    let status: GitStatus?

    var body: some View {
        if let status {
            pill(for: status)
        }
    }

    private func pill(for status: GitStatus) -> some View {
        HStack(spacing: 6) {
            Label(status.branchDisplay, systemImage: "arrow.triangle.branch")
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.secondary)

            if status.ahead > 0 {
                Text("↑\(status.ahead)").foregroundStyle(.secondary)
            }
            if status.behind > 0 {
                Text("↓\(status.behind)").foregroundStyle(.secondary)
            }
            if let worktree = status.worktree {
                worktreeChip(worktree)
            }
            if status.dirty > 0 {
                Text("*\(status.dirty)").foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.quaternary, in: Capsule())
        .accessibilityIdentifier("git-pill")
        .accessibilityValue(status.branchDisplay)
    }

    /// A small capsule chip naming a linked worktree.
    private func worktreeChip(_ name: String) -> some View {
        Text(name)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.quaternary, in: Capsule())
    }
}

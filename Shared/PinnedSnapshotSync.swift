import SwiftUI
import SwiftData
import WidgetKit

/// An invisible view that keeps the App Group snapshot (read by the widget) in
/// sync with the live SwiftData store. It runs a standing `@Query` for pinned,
/// non-archived notes, so it fires on *any* mutation — new note, edit, pin,
/// unpin, archive, delete — as well as on CloudKit remote changes. Mounting it
/// once inside `NoteListView` covers both the macOS HUD and the iOS app without
/// having to hook every individual save site.
struct PinnedSnapshotSync: View {
    // Filtering on a Bool in a #Predicate is fine; only *sorting* by a Bool
    // key path fails to compile, so we sort by createdAt and rely on the query.
    @Query(
        filter: #Predicate<Note> { $0.isPinned && !$0.isArchived },
        sort: \Note.createdAt,
        order: .reverse
    )
    private var pinnedNotes: [Note]

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onAppear { write() }
            .onChange(of: signature) { _, _ in write() }
    }

    /// A cheap fingerprint of the pinned set: changes whenever a note is added,
    /// removed, reordered, or edited (content edits bump `updatedAt`).
    private var signature: String {
        pinnedNotes
            .map { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" }
            .joined(separator: "|")
    }

    private func write() {
        let snapshots = pinnedNotes.prefix(SharedStore.maxPinned).map {
            PinnedNoteSnapshot(id: $0.id, content: $0.content, updatedAt: $0.updatedAt)
        }
        SharedStore.savePinned(Array(snapshots))
        WidgetCenter.shared.reloadAllTimelines()
    }
}

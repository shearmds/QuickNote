import Foundation

/// A lightweight, Codable snapshot of a pinned note. The app writes these into a
/// shared App Group container on every change; the widget reads them back. This
/// avoids exposing the SwiftData/CloudKit store to the widget process — the
/// widget only ever sees this flat, read-only projection.
struct PinnedNoteSnapshot: Codable, Identifiable, Hashable {
    let id: UUID
    /// First non-empty line of the note (mirrors the app's row `titleLine`).
    let title: String
    /// The remaining text after the title line, collapsed to a short preview.
    let preview: String
    let updatedAt: Date

    /// Builds a snapshot from raw note content, using the same "first non-empty
    /// line is the title" rule the in-app note rows use.
    init(id: UUID, content: String, updatedAt: Date) {
        self.id = id
        self.updatedAt = updatedAt

        let lines = content.split(whereSeparator: \.isNewline).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        let firstNonEmpty = lines.firstIndex(where: { !$0.isEmpty })

        if let firstNonEmpty {
            self.title = lines[firstNonEmpty]
            let rest = lines[(firstNonEmpty + 1)...].filter { !$0.isEmpty }
            self.preview = rest.joined(separator: " ")
        } else {
            self.title = "Untitled Note"
            self.preview = ""
        }
    }
}

/// Read/write access to the pinned-notes snapshot shared between the app and the
/// widget via the App Group container.
enum SharedStore {
    /// Must match the App Group capability enabled on BOTH the app and the widget
    /// target in Xcode (Signing & Capabilities → App Groups).
    static let appGroupID = "group.com.shearair.QuickNote"

    /// URL scheme used to deep-link from a widget back into a specific note.
    static let urlScheme = "quicknote"

    /// The maximum number of pinned notes we persist for the widget. The large
    /// widget shows the most; smaller families show a subset.
    static let maxPinned = 8

    private static let fileName = "pinned-notes.json"

    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(fileName)
    }

    /// Deep-link URL for a given note id, e.g. `quicknote://note/<uuid>`.
    static func deepLinkURL(for id: UUID) -> URL? {
        URL(string: "\(urlScheme)://note/\(id.uuidString)")
    }

    /// Parses a note id out of a `quicknote://note/<uuid>` URL, if present.
    static func noteID(from url: URL) -> UUID? {
        guard url.scheme == urlScheme, url.host == "note" else { return nil }
        let raw = url.lastPathComponent
        return UUID(uuidString: raw)
    }

    static func savePinned(_ notes: [PinnedNoteSnapshot]) {
        guard let fileURL else { return }
        do {
            let data = try JSONEncoder().encode(notes)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("SharedStore: failed to write pinned snapshot: \(error)")
        }
    }

    static func loadPinned() -> [PinnedNoteSnapshot] {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([PinnedNoteSnapshot].self, from: data)) ?? []
    }
}

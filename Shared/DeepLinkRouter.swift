import Foundation
import SwiftUI
import Combine

/// Carries a widget deep-link (`quicknote://note/<uuid>`) from wherever the URL
/// is received — the iOS scene's `onOpenURL` or the macOS `AppDelegate` — into
/// `NoteListView`, which resolves it to a note and opens it (iPad detail pane).
@MainActor
final class DeepLinkRouter: ObservableObject {
    static let shared = DeepLinkRouter()
    private init() {}

    /// The note the user tapped in a widget, waiting to be opened. `NoteListView`
    /// clears it once handled.
    @Published var pendingNoteID: UUID?

    func handle(_ url: URL) {
        if let id = SharedStore.noteID(from: url) {
            pendingNoteID = id
        }
    }
}

import SwiftUI
import SwiftData

@main
struct QuickNoteApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    var body: some Scene {
        #if os(iOS)
        WindowGroup {
            ContentView()
                .modelContainer(AppModelContainer.shared)
        }
        #else
        // macOS: Menu Bar Extra is our only persistent UI scene.
        // It provides quick access and a way to quit.
        MenuBarExtra("QuickNote", systemImage: "square.and.pencil") {
            Button("Show HUD (⌥Space)") {
                HUDWindowController.shared.show()
            }
            Divider()
            Button("Quit QuickNote") {
                NSApplication.shared.terminate(nil)
            }
        }
        #endif
    }
}

/// Single, process-wide SwiftData container with CloudKit sync enabled so notes
/// sync across the user's devices. CloudKit integration requires that every
/// `Note` property has a default value (see `Note.swift`) and that there are no
/// unique constraints — both hold here.
enum AppModelContainer {
    static let shared: ModelContainer = {
        do {
            let configuration = ModelConfiguration(cloudKitDatabase: .automatic)
            return try ModelContainer(for: Note.self, configurations: configuration)
        } catch {
            // Fall back to a local-only store so the app still launches when
            // CloudKit is unavailable (e.g. the user isn't signed into iCloud).
            print("CloudKit container unavailable, falling back to local store: \(error)")
            if let local = try? ModelContainer(for: Note.self) {
                return local
            }
            fatalError("Unable to create a SwiftData ModelContainer: \(error)")
        }
    }()
}

struct ContentView: View {
    var body: some View {
        NoteListView()
    }
}

#if os(macOS)
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Build the HUD view on the shared (CloudKit-backed) container.
        let hudView = NoteListView()
            .modelContainer(AppModelContainer.shared)

        // Setup the window with this view
        HUDWindowController.shared.setup(with: hudView)

        // Register hotkey trigger action
        HotkeyManager.shared.onTrigger = {
            HUDWindowController.shared.toggle()
        }

        // Register the hotkey
        HotkeyManager.shared.register()
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.unregister()
    }
}
#endif

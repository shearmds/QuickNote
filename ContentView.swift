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
                .modelContainer(for: Note.self)
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

struct ContentView: View {
    var body: some View {
        NoteListView()
            .preferredColorScheme(.light) // Clean light look by default
    }
}

#if os(macOS)
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize the SwiftData container manually for the HUD window
        do {
            let container = try ModelContainer(for: Note.self)
            
            // Set up HUD View with SwiftData container
            let hudView = NoteListView()
                .modelContainer(container)
                .preferredColorScheme(.light)
            
            // Setup the window with this view
            HUDWindowController.shared.setup(with: hudView)
            
            // Register hotkey trigger action
            HotkeyManager.shared.onTrigger = {
                HUDWindowController.shared.toggle()
            }
            
            // Register the hotkey
            HotkeyManager.shared.register()
            
        } catch {
            print("Failed to initialize SwiftData model container: \(error)")
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.unregister()
    }
}
#endif

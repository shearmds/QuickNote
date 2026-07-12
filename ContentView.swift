import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

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
                .onOpenURL { DeepLinkRouter.shared.handle($0) }
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

        // This is a menu-bar agent app with no WindowGroup, so macOS does NOT
        // deliver `quicknote://` opens through `application(_:open:)`. Register a
        // Get-URL Apple Event handler — the reliable path for agent apps — so
        // widget taps route into the app.
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )

        // This is a multiplatform app: iOS builds share the bundle id
        // `com.shearair.QuickNote` and also claim the `quicknote:` scheme, so
        // LaunchServices (which keys the scheme's default handler by bundle id)
        // can route widget taps to a stale/iOS build that can't handle them.
        // Force THIS running app — by its own bundle path — to be the default
        // handler on every launch so widget deep links always reach us.
        NSWorkspace.shared.setDefaultApplication(
            at: Bundle.main.bundleURL,
            toOpenURLsWithScheme: SharedStore.urlScheme
        ) { error in
            if let error { NSLog("QuickNote: could not claim \(SharedStore.urlScheme): scheme: \(error)") }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.unregister()
    }

    @objc private func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard
            let string = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
            let url = URL(string: string)
        else { return }
        open(url)
    }

    // Also handle the standard open path, in case the OS ever delivers it here.
    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach(open)
    }

    /// Routes a `quicknote://note/<uuid>` deep link: bring the HUD forward and
    /// hand the note id to the list.
    private func open(_ url: URL) {
        DeepLinkRouter.shared.handle(url)
        HUDWindowController.shared.show()
    }
}
#endif

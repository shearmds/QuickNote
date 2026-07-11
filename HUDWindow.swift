#if os(macOS)
import AppKit
import SwiftUI

@MainActor
class HUDWindow: NSWindow {
    init(contentView: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 650, height: 420),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        self.isReleasedWhenClosed = false
        self.level = .statusBar // Float above standard windows and menu bar
        self.backgroundColor = .clear
        self.isMovableByWindowBackground = true
        self.hasShadow = true
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        
        // Create the glassmorphic background
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = .hudWindow // Modern HUD look
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.autoresizingMask = [.width, .height]
        
        // Setup a container view to hold the visual effect and SwiftUI content
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 650, height: 420))
        containerView.autoresizingMask = [.width, .height]
        visualEffectView.frame = containerView.bounds
        containerView.addSubview(visualEffectView)
        
        contentView.frame = containerView.bounds
        contentView.autoresizingMask = [.width, .height]
        containerView.addSubview(contentView)
        
        self.contentView = containerView
        
        // Add corner radius to window content view
        if let contentView = self.contentView {
            contentView.wantsLayer = true
            contentView.layer?.cornerRadius = 16.0
            contentView.layer?.masksToBounds = true
        }
        
        self.center()
        self.orderOut(nil)
    }
    
    override var canBecomeKey: Bool {
        return true
    }
    
    override var canBecomeMain: Bool {
        return true
    }
    
    // Support Esc key to close window
    override func cancelOperation(_ sender: Any?) {
        HUDWindowController.shared.hide()
    }
}

@MainActor
class HUDWindowController: NSObject, NSWindowDelegate {
    static let shared = HUDWindowController()
    
    var window: HUDWindow?
    
    func setup<V: View>(with view: V) {
        let hostingView = NSHostingView(rootView: view)
        let hudWindow = HUDWindow(contentView: hostingView)
        hudWindow.delegate = self
        self.window = hudWindow
    }
    
    func toggle() {
        guard let window = window else { return }
        if window.isVisible {
            hide()
        } else {
            show()
        }
    }
    
    func show() {
        guard let window = window else { return }
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func hide() {
        window?.orderOut(nil)
    }
    
    func windowDidResignKey(_ notification: Notification) {
        // Auto-hide when user clicks away from the HUD,
        // but NOT if there is a sheet or a modal window (like a file export panel) active.
        if let window = window, window.attachedSheet != nil {
            return
        }
        if NSApp.modalWindow != nil {
            return
        }
        hide()
    }
}
#endif

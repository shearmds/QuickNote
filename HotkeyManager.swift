#if os(macOS)
import Carbon
import AppKit

class HotkeyManager {
    static let shared = HotkeyManager()
    
    var onTrigger: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    
    func register() {
        // Clean up previous if any
        unregister()
        
        // Register Option + Space
        // Spacebar key code is 49. Option modifier is optionKey (from Carbon)
        let signature = OSType(0x514E4F54) // 'QNOT' in hex
        let hotKeyID = EventHotKeyID(signature: signature, id: 1)
        
        let status = RegisterEventHotKey(
            UInt32(49), 
            UInt32(optionKey), 
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        
        if status != noErr {
            print("Failed to register Option+Space hotkey: \(status)")
        } else {
            print("Successfully registered Option+Space hotkey")
        }
        
        setupEventHandler()
    }
    
    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let ref = eventHandlerRef {
            RemoveEventHandler(ref)
            eventHandlerRef = nil
        }
    }
    
    private func setupEventHandler() {
        var eventType = EventTypeSpec()
        eventType.eventClass = OSType(kEventClassKeyboard)
        eventType.eventKind = UInt32(kEventHotKeyPressed)
        
        let eventHandler: EventHandlerUPP = { (_, _, _) -> OSStatus in
            HotkeyManager.shared.handleKeyPress()
            return noErr
        }
        
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            eventHandler,
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )
        
        if status != noErr {
            print("Failed to install Carbon event handler: \(status)")
        }
    }
    
    private func handleKeyPress() {
        DispatchQueue.main.async {
            self.onTrigger?()
        }
    }
}
#endif

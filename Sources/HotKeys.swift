import Carbon.HIToolbox
import Foundation

/// System-wide shortcuts. Carbon hot keys need no Accessibility permission.
final class HotKeys {
    struct Binding {
        let keyCode: Int
        let modifiers: Int
        let action: () -> Void
    }

    private static var actions: [UInt32: () -> Void] = [:]
    private var handler: EventHandlerRef?
    private var registered: [EventHotKeyRef] = []

    init(_ bindings: [Binding]) {
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKey = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKey)
            let key = hotKey.id
            if status == noErr { DispatchQueue.main.async { HotKeys.actions[key]?() } }
            return noErr
        }, 1, &pressed, nil, &handler)

        for (index, binding) in bindings.enumerated() {
            let id = UInt32(index + 1)
            HotKeys.actions[id] = binding.action
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: OSType(0x4843_484D), id: id)   // 'HCHM'
            if RegisterEventHotKey(UInt32(binding.keyCode), UInt32(binding.modifiers), hotKeyID,
                                   GetApplicationEventTarget(), 0, &ref) == noErr, let ref {
                registered.append(ref)
            }
        }
    }
}

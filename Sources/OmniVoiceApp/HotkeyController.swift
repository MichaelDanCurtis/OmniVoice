import Carbon
import Foundation
import OmniVoiceCore

@MainActor
final class HotkeyController {
    enum Event {
        case dictationPressed
        case dictationReleased
        case stylePressed
    }

    enum HotkeyError: Error {
        case handlerInstallFailed(OSStatus)
        case registrationFailed(OSStatus)
    }

    var onEvent: ((Event) -> Void)?

    private var dictationHotkey: EventHotKeyRef?
    private var styleHotkey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var isRegistered = false

    func register(dictation: HotkeyBinding, style: HotkeyBinding) throws {
        guard !isRegistered else { return }

        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, eventRef, userData in
                guard let userData, let eventRef else { return noErr }

                var hotkeyID = EventHotKeyID()
                GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotkeyID
                )

                let kind = GetEventKind(eventRef)
                Task { @MainActor in
                    let controller = Unmanaged<HotkeyController>.fromOpaque(userData).takeUnretainedValue()
                    controller.handle(hotkeyID: hotkeyID, kind: kind)
                }
                return noErr
            },
            eventTypes.count,
            &eventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        guard handlerStatus == noErr else {
            throw HotkeyError.handlerInstallFailed(handlerStatus)
        }

        let dictationID = EventHotKeyID(signature: OSType(0x4F4D4E49), id: 1)
        let dictationStatus = RegisterEventHotKey(
            dictation.keyCode,
            dictation.modifiers,
            dictationID,
            GetApplicationEventTarget(),
            UInt32(kEventHotKeyExclusive),
            &dictationHotkey
        )
        guard dictationStatus == noErr else {
            unregister()
            throw HotkeyError.registrationFailed(dictationStatus)
        }

        let styleID = EventHotKeyID(signature: OSType(0x4F4D4E49), id: 2)
        let styleStatus = RegisterEventHotKey(
            style.keyCode,
            style.modifiers,
            styleID,
            GetApplicationEventTarget(),
            UInt32(kEventHotKeyExclusive),
            &styleHotkey
        )
        guard styleStatus == noErr else {
            unregister()
            throw HotkeyError.registrationFailed(styleStatus)
        }

        isRegistered = true
    }

    func unregister() {
        if let dictationHotkey {
            UnregisterEventHotKey(dictationHotkey)
        }
        if let styleHotkey {
            UnregisterEventHotKey(styleHotkey)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
        dictationHotkey = nil
        styleHotkey = nil
        eventHandler = nil
        isRegistered = false
    }

    private func handle(hotkeyID: EventHotKeyID, kind: UInt32) {
        if hotkeyID.id == 1 {
            onEvent?(kind == UInt32(kEventHotKeyPressed) ? .dictationPressed : .dictationReleased)
        } else if hotkeyID.id == 2, kind == UInt32(kEventHotKeyPressed) {
            onEvent?(.stylePressed)
        }
    }
}

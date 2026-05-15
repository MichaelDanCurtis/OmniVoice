import Carbon
import AppKit
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
    private var dictationModifierChord: HotkeyBinding?
    private var styleModifierChord: HotkeyBinding?
    private var localModifierMonitor: Any?
    private var globalModifierMonitor: Any?
    private var isDictationModifierActive = false
    private var isStyleModifierActive = false
    private var isRegistered = false

    func register(dictation: HotkeyBinding, style: HotkeyBinding) throws {
        guard !isRegistered else { return }

        dictationModifierChord = dictation.isModifierOnly ? dictation : nil
        styleModifierChord = style.isModifierOnly ? style : nil

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

        if !dictation.isModifierOnly {
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
        }

        if !style.isModifierOnly {
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
        }

        if dictation.isModifierOnly || style.isModifierOnly {
            installModifierMonitors()
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
        if let localModifierMonitor {
            NSEvent.removeMonitor(localModifierMonitor)
        }
        if let globalModifierMonitor {
            NSEvent.removeMonitor(globalModifierMonitor)
        }
        dictationHotkey = nil
        styleHotkey = nil
        eventHandler = nil
        dictationModifierChord = nil
        styleModifierChord = nil
        localModifierMonitor = nil
        globalModifierMonitor = nil
        isDictationModifierActive = false
        isStyleModifierActive = false
        isRegistered = false
    }

    private func handle(hotkeyID: EventHotKeyID, kind: UInt32) {
        if hotkeyID.id == 1 {
            onEvent?(kind == UInt32(kEventHotKeyPressed) ? .dictationPressed : .dictationReleased)
        } else if hotkeyID.id == 2, kind == UInt32(kEventHotKeyPressed) {
            onEvent?(.stylePressed)
        }
    }

    private func installModifierMonitors() {
        localModifierMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            let modifiers = Self.carbonModifiers(from: event.modifierFlags)
            Task { @MainActor [weak self] in
                self?.handleModifierState(modifiers)
            }
            return event
        }

        globalModifierMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            let modifiers = Self.carbonModifiers(from: event.modifierFlags)
            Task { @MainActor [weak self] in
                self?.handleModifierState(modifiers)
            }
        }
    }

    private func handleModifierState(_ modifiers: UInt32) {
        if let dictationModifierChord {
            let isActive = modifiers == dictationModifierChord.modifiers
            if isActive, !isDictationModifierActive {
                isDictationModifierActive = true
                onEvent?(.dictationPressed)
            } else if !isActive, isDictationModifierActive {
                isDictationModifierActive = false
                onEvent?(.dictationReleased)
            }
        }

        if let styleModifierChord {
            let isActive = modifiers == styleModifierChord.modifiers
            if isActive, !isStyleModifierActive {
                isStyleModifierActive = true
                onEvent?(.stylePressed)
            } else if !isActive {
                isStyleModifierActive = false
            }
        }
    }

    nonisolated private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        HotkeyBinding.carbonModifiers(
            command: flags.contains(.command),
            option: flags.contains(.option),
            control: flags.contains(.control),
            shift: flags.contains(.shift)
        )
    }
}

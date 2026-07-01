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
        case hotMenuPressed
        case hotMenuReleased
        case transcriptCachePressed
        case bubbleInsert
        case bubbleCopy
        case bubbleDismiss
        case teachCorrectionPressed
    }

    enum HotkeyError: Error {
        case handlerInstallFailed(OSStatus)
        case registrationFailed(OSStatus)
    }

    var onEvent: ((Event) -> Void)?

    private var dictationHotkey: EventHotKeyRef?
    private var additionalDictationHotkeys: [EventHotKeyRef?] = []
    private var styleHotkey: EventHotKeyRef?
    private var hotMenuHotkey: EventHotKeyRef?
    private var transcriptCacheHotkey: EventHotKeyRef?
    private var bubbleInsertHotkey: EventHotKeyRef?
    private var bubbleCopyHotkey: EventHotKeyRef?
    private var bubbleDismissHotkey: EventHotKeyRef?
    private var teachCorrectionHotkey: EventHotKeyRef?   // fixed ⌃⌥T
    private var eventHandler: EventHandlerRef?
    private var dictationModifierChords: [HotkeyBinding] = []
    private var styleModifierChord: HotkeyBinding?
    private var hotMenuModifierChord: HotkeyBinding?
    private var transcriptCacheModifierChord: HotkeyBinding?
    private var localModifierMonitor: Any?
    private var globalModifierMonitor: Any?
    private var activeDictationModifierChord: UInt32?
    private var isStyleModifierActive = false
    private var isHotMenuModifierActive = false
    private var isTranscriptCacheModifierActive = false
    private var isRegistered = false

    func register(
        dictation: HotkeyBinding,
        additionalDictation: [HotkeyBinding],
        style: HotkeyBinding,
        hotMenu: HotkeyBinding,
        transcriptCache: HotkeyBinding
    ) throws {
        guard !isRegistered else { return }

        let dictationBindings = [dictation] + additionalDictation
        dictationModifierChords = dictationBindings.filter(\.isModifierOnly)
        styleModifierChord = style.isModifierOnly ? style : nil
        hotMenuModifierChord = hotMenu.isModifierOnly ? hotMenu : nil
        transcriptCacheModifierChord = transcriptCache.isModifierOnly ? transcriptCache : nil

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

        for (index, binding) in dictationBindings.enumerated() where !binding.isModifierOnly {
            let dictationID = EventHotKeyID(signature: OSType(0x4F4D4E49), id: UInt32(index == 0 ? 1 : 100 + index))
            var hotkeyRef: EventHotKeyRef?
            let dictationStatus = RegisterEventHotKey(
                binding.keyCode,
                binding.modifiers,
                dictationID,
                GetApplicationEventTarget(),
                UInt32(kEventHotKeyExclusive),
                &hotkeyRef
            )
            guard dictationStatus == noErr else {
                unregister()
                throw HotkeyError.registrationFailed(dictationStatus)
            }
            if index == 0 {
                dictationHotkey = hotkeyRef
            } else {
                additionalDictationHotkeys.append(hotkeyRef)
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

        if !hotMenu.isModifierOnly {
            let hotMenuID = EventHotKeyID(signature: OSType(0x4F4D4E49), id: 3)
            let hotMenuStatus = RegisterEventHotKey(
                hotMenu.keyCode,
                hotMenu.modifiers,
                hotMenuID,
                GetApplicationEventTarget(),
                UInt32(kEventHotKeyExclusive),
                &hotMenuHotkey
            )
            guard hotMenuStatus == noErr else {
                unregister()
                throw HotkeyError.registrationFailed(hotMenuStatus)
            }
        }

        if !transcriptCache.isModifierOnly {
            let transcriptCacheID = EventHotKeyID(signature: OSType(0x4F4D4E49), id: 4)
            let transcriptCacheStatus = RegisterEventHotKey(
                transcriptCache.keyCode,
                transcriptCache.modifiers,
                transcriptCacheID,
                GetApplicationEventTarget(),
                UInt32(kEventHotKeyExclusive),
                &transcriptCacheHotkey
            )
            guard transcriptCacheStatus == noErr else {
                unregister()
                throw HotkeyError.registrationFailed(transcriptCacheStatus)
            }
        }

        if dictationBindings.contains(where: \.isModifierOnly)
            || style.isModifierOnly
            || hotMenu.isModifierOnly
            || transcriptCache.isModifierOnly {
            installModifierMonitors()
        }

        // Fixed teach-correction hotkey: ⌃⌥T (keyCode 17, control+option = 6144). Best-effort
        // — if the combo is taken, teaching is still available; auto-detect is the primary path.
        let teachID = EventHotKeyID(signature: OSType(0x4F4D4E49), id: 8)
        RegisterEventHotKey(17, 6_144, teachID, GetApplicationEventTarget(), UInt32(kEventHotKeyExclusive), &teachCorrectionHotkey)

        isRegistered = true
    }

    func unregister() {
        if let dictationHotkey {
            UnregisterEventHotKey(dictationHotkey)
        }
        for hotkey in additionalDictationHotkeys {
            if let hotkey {
                UnregisterEventHotKey(hotkey)
            }
        }
        if let styleHotkey {
            UnregisterEventHotKey(styleHotkey)
        }
        if let hotMenuHotkey {
            UnregisterEventHotKey(hotMenuHotkey)
        }
        if let transcriptCacheHotkey {
            UnregisterEventHotKey(transcriptCacheHotkey)
        }
        unregisterBubbleActions()
        if let teachCorrectionHotkey {
            UnregisterEventHotKey(teachCorrectionHotkey)
        }
        teachCorrectionHotkey = nil
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
        additionalDictationHotkeys = []
        styleHotkey = nil
        hotMenuHotkey = nil
        transcriptCacheHotkey = nil
        eventHandler = nil
        dictationModifierChords = []
        styleModifierChord = nil
        hotMenuModifierChord = nil
        transcriptCacheModifierChord = nil
        localModifierMonitor = nil
        globalModifierMonitor = nil
        activeDictationModifierChord = nil
        isStyleModifierActive = false
        isHotMenuModifierActive = false
        isTranscriptCacheModifierActive = false
        isRegistered = false
    }

    private func handle(hotkeyID: EventHotKeyID, kind: UInt32) {
        if hotkeyID.id == 1 || (100..<200).contains(hotkeyID.id) {
            onEvent?(kind == UInt32(kEventHotKeyPressed) ? .dictationPressed : .dictationReleased)
        } else if hotkeyID.id == 2, kind == UInt32(kEventHotKeyPressed) {
            onEvent?(.stylePressed)
        } else if hotkeyID.id == 3 {
            onEvent?(kind == UInt32(kEventHotKeyPressed) ? .hotMenuPressed : .hotMenuReleased)
        } else if hotkeyID.id == 4, kind == UInt32(kEventHotKeyPressed) {
            onEvent?(.transcriptCachePressed)
        } else if hotkeyID.id == 5, kind == UInt32(kEventHotKeyPressed) {
            onEvent?(.bubbleInsert)
        } else if hotkeyID.id == 6, kind == UInt32(kEventHotKeyPressed) {
            onEvent?(.bubbleCopy)
        } else if hotkeyID.id == 7, kind == UInt32(kEventHotKeyPressed) {
            onEvent?(.bubbleDismiss)
        } else if hotkeyID.id == 8, kind == UInt32(kEventHotKeyPressed) {
            onEvent?(.teachCorrectionPressed)
        }
    }

    /// Registers ⟨modifiers⟩+I / +C / +D as global, exclusive hotkeys for the Ask
    /// bubble's Insert / Copy / Dismiss actions. Call when the bubble opens; pair with
    /// `unregisterBubbleActions()` on close so the combos aren't swallowed app-wide.
    /// Reuses the InstallEventHandler from `register(...)`, so that must run first.
    func registerBubbleActions(modifiers: UInt32) {
        unregisterBubbleActions()
        bubbleInsertHotkey = registerActionHotkey(keyCode: 34, modifiers: modifiers, id: 5)   // I
        bubbleCopyHotkey = registerActionHotkey(keyCode: 8, modifiers: modifiers, id: 6)      // C
        bubbleDismissHotkey = registerActionHotkey(keyCode: 2, modifiers: modifiers, id: 7)   // D
    }

    func unregisterBubbleActions() {
        for hotkey in [bubbleInsertHotkey, bubbleCopyHotkey, bubbleDismissHotkey] {
            if let hotkey {
                UnregisterEventHotKey(hotkey)
            }
        }
        bubbleInsertHotkey = nil
        bubbleCopyHotkey = nil
        bubbleDismissHotkey = nil
    }

    private func registerActionHotkey(keyCode: UInt32, modifiers: UInt32, id: UInt32) -> EventHotKeyRef? {
        let hotkeyID = EventHotKeyID(signature: OSType(0x4F4D4E49), id: id)
        var hotkeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            UInt32(kEventHotKeyExclusive),
            &hotkeyRef
        )
        return status == noErr ? hotkeyRef : nil
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
        let activeDictationChord = dictationModifierChords.first { $0.modifiers == modifiers }?.modifiers
        if activeDictationChord != activeDictationModifierChord {
            if activeDictationModifierChord != nil {
                activeDictationModifierChord = nil
                onEvent?(.dictationReleased)
            }
            if let activeDictationChord {
                activeDictationModifierChord = activeDictationChord
                onEvent?(.dictationPressed)
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

        if let hotMenuModifierChord {
            let isActive = modifiers == hotMenuModifierChord.modifiers
            if isActive, !isHotMenuModifierActive {
                isHotMenuModifierActive = true
                onEvent?(.hotMenuPressed)
            } else if !isActive, isHotMenuModifierActive {
                isHotMenuModifierActive = false
                onEvent?(.hotMenuReleased)
            }
        }

        if let transcriptCacheModifierChord {
            let isActive = modifiers == transcriptCacheModifierChord.modifiers
            if isActive, !isTranscriptCacheModifierActive {
                isTranscriptCacheModifierActive = true
                onEvent?(.transcriptCachePressed)
            } else if !isActive {
                isTranscriptCacheModifierActive = false
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

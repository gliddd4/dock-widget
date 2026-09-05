//
//  OptionNumberHotKeys.swift
//  Dock
//
//  Registers global hotkeys for the Touch Bar dock:
//    Option+1..9  -> switch to the Nth app in the dock
//    Option+[     -> shrink the dock item (icon) size
//    Option+]     -> grow the dock item (icon) size
//
//  Some apps (FL Studio) use Option+number themselves. While one of them is
//  the frontmost app, the dock's app-switch hotkeys switch to Option+Shift+1..9
//  and the plain Option+number combos are released so the app still gets them.
//

import Foundation
import Carbon

final class OptionNumberHotKeys {

	static let shared = OptionNumberHotKeys()

	private var handler: ((Int) -> Void)?
	private var handlerInstalled = false
	private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
	private var appSwitchRequiresShift = false
	private let signature = OSType(0x4F4B4544) // 'OKED'

	/// (keyCode, modifier, id). ids 1-9 are app switch (Option, or Option+Shift
	/// while an app that owns Option+number is frontmost);
	/// 10 = shrink, 11 = grow, 12 = move up, 13 = move down (Option+[/]),
	/// 14 = play/pause, 15/16 = tracks, 17/18 = volume (Option).
	private let otherHotKeys: [(UInt32, Int, UInt32)] = [
		(UInt32(kVK_ANSI_LeftBracket), 10, UInt32(optionKey)),
		(UInt32(kVK_ANSI_RightBracket), 11, UInt32(optionKey)),
		(UInt32(kVK_ANSI_LeftBracket), 12, UInt32(optionKey | shiftKey)),
		(UInt32(kVK_ANSI_RightBracket), 13, UInt32(optionKey | shiftKey)),
		(UInt32(kVK_Space), 14, UInt32(optionKey)),
		(UInt32(kVK_LeftArrow), 15, UInt32(optionKey)),
		(UInt32(kVK_RightArrow), 16, UInt32(optionKey)),
		(UInt32(kVK_UpArrow), 17, UInt32(optionKey)),
		(UInt32(kVK_DownArrow), 18, UInt32(optionKey))
	]

	/// Flip the app-switch hotkeys (1-9) between Option and Option+Shift so a
	/// frontmost app that owns Option+number (FL Studio) keeps its combos.
	func setAppSwitchRequiresShift(_ requiresShift: Bool) {
		guard handlerInstalled, requiresShift != appSwitchRequiresShift else {
			return
		}
		appSwitchRequiresShift = requiresShift
		for id in 1...9 {
			unregisterHotKey(id: id)
		}
		registerAppSwitchHotKeys()
	}

	func register(handler: @escaping (Int) -> Void) {
		self.handler = handler
		guard !handlerInstalled else {
			return
		}
		var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
		let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
			var hotKeyID = EventHotKeyID()
			let result = GetEventParameter(event,
										   EventParamName(kEventParamDirectObject),
										   EventParamType(typeEventHotKeyID),
										   nil,
										   MemoryLayout<EventHotKeyID>.size,
										   nil,
										   &hotKeyID)
			guard result == noErr else {
				return result
			}
			let index = Int(hotKeyID.id)
			if (1...18).contains(index) {
				DispatchQueue.main.async {
					OptionNumberHotKeys.shared.handler?(index)
				}
			}
			return noErr
		}, 1, &eventType, nil, nil)
		guard status == noErr else {
			NSLog("[DockWidget]: Failed to install hotkey event handler: \(status)")
			return
		}
		handlerInstalled = true
		for (keyCode, id, modifiers) in otherHotKeys {
			registerHotKey(id: id, keyCode: keyCode, modifiers: modifiers)
		}
		registerAppSwitchHotKeys()
	}

	// MARK: App-switch hotkeys (1-9)

	private var appSwitchModifiers: UInt32 {
		return UInt32(appSwitchRequiresShift ? (optionKey | shiftKey) : optionKey)
	}

	private func registerAppSwitchHotKeys() {
		let keyCodes: [UInt32] = [UInt32(kVK_ANSI_1), UInt32(kVK_ANSI_2), UInt32(kVK_ANSI_3), UInt32(kVK_ANSI_4),
								  UInt32(kVK_ANSI_5), UInt32(kVK_ANSI_6), UInt32(kVK_ANSI_7), UInt32(kVK_ANSI_8),
								  UInt32(kVK_ANSI_9)]
		for id in 1...9 {
			registerHotKey(id: id, keyCode: keyCodes[id - 1], modifiers: appSwitchModifiers)
		}
	}

	// MARK: Registration helpers

	private func registerHotKey(id: Int, keyCode: UInt32, modifiers: UInt32) {
		var hotKeyRef: EventHotKeyRef?
		let hotKeyID = EventHotKeyID(signature: signature, id: UInt32(id))
		let registerStatus = RegisterEventHotKey(keyCode,
												 modifiers,
												 hotKeyID,
												 GetApplicationEventTarget(),
												 0,
												 &hotKeyRef)
		guard registerStatus == noErr, let hotKeyRef = hotKeyRef else {
			NSLog("[DockWidget]: Failed to register hotkey for id \(id): \(registerStatus)")
			return
		}
		hotKeyRefs[UInt32(id)] = hotKeyRef
	}

	private func unregisterHotKey(id: Int) {
		guard let hotKeyRef = hotKeyRefs.removeValue(forKey: UInt32(id)) else {
			return
		}
		UnregisterEventHotKey(hotKeyRef)
	}

}

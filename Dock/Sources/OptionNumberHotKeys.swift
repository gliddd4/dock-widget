//
//  OptionNumberHotKeys.swift
//  Dock
//
//  Registers global hotkeys for the Touch Bar dock:
//    Option+1..9  -> switch to the Nth app in the dock
//    Option+[     -> shrink the dock item (icon) size
//    Option+]     -> grow the dock item (icon) size
//    Option held  -> app switcher (search keys a-z/0/delete registered
//                    only while the switcher is active, so normal
//                    Option+letter typing keeps working everywhere else)
//

import Foundation
import Carbon

final class OptionNumberHotKeys {

	static let shared = OptionNumberHotKeys()

	private var handler: ((Int) -> Void)?
	private var handlerInstalled = false
	private var hotKeyRefs: [EventHotKeyRef?] = []

	/// (keyCode, modifier, id). ids 1-9 are app switch;
	/// 10 = shrink, 11 = grow, 12 = move up, 13 = move down.
	private let hotKeys: [(UInt32, Int, UInt32)] = [
		(UInt32(kVK_ANSI_1), 1, UInt32(optionKey)), (UInt32(kVK_ANSI_2), 2, UInt32(optionKey)),
		(UInt32(kVK_ANSI_3), 3, UInt32(optionKey)), (UInt32(kVK_ANSI_4), 4, UInt32(optionKey)),
		(UInt32(kVK_ANSI_5), 5, UInt32(optionKey)), (UInt32(kVK_ANSI_6), 6, UInt32(optionKey)),
		(UInt32(kVK_ANSI_7), 7, UInt32(optionKey)), (UInt32(kVK_ANSI_8), 8, UInt32(optionKey)),
		(UInt32(kVK_ANSI_9), 9, UInt32(optionKey)),
		(UInt32(kVK_ANSI_LeftBracket), 10, UInt32(optionKey)),
		(UInt32(kVK_ANSI_RightBracket), 11, UInt32(optionKey)),
		(UInt32(kVK_ANSI_LeftBracket), 12, UInt32(optionKey | shiftKey)),
		(UInt32(kVK_ANSI_RightBracket), 13, UInt32(optionKey | shiftKey))
	]

	// MARK: App switcher search keys (registered only while Option is held)

	private var searchHandler: ((String) -> Void)?
	private var searchHotKeyRefs: [EventHotKeyRef?] = []

	/// (keyCode, letter index 0-25). Option+<letter> -> search input.
	private let letterKeyCodes: [(UInt32, Int)] = [
		(UInt32(kVK_ANSI_A), 0), (UInt32(kVK_ANSI_B), 1), (UInt32(kVK_ANSI_C), 2), (UInt32(kVK_ANSI_D), 3),
		(UInt32(kVK_ANSI_E), 4), (UInt32(kVK_ANSI_F), 5), (UInt32(kVK_ANSI_G), 6), (UInt32(kVK_ANSI_H), 7),
		(UInt32(kVK_ANSI_I), 8), (UInt32(kVK_ANSI_J), 9), (UInt32(kVK_ANSI_K), 10), (UInt32(kVK_ANSI_L), 11),
		(UInt32(kVK_ANSI_M), 12), (UInt32(kVK_ANSI_N), 13), (UInt32(kVK_ANSI_O), 14), (UInt32(kVK_ANSI_P), 15),
		(UInt32(kVK_ANSI_Q), 16), (UInt32(kVK_ANSI_R), 17), (UInt32(kVK_ANSI_S), 18), (UInt32(kVK_ANSI_T), 19),
		(UInt32(kVK_ANSI_U), 20), (UInt32(kVK_ANSI_V), 21), (UInt32(kVK_ANSI_W), 22), (UInt32(kVK_ANSI_X), 23),
		(UInt32(kVK_ANSI_Y), 24), (UInt32(kVK_ANSI_Z), 25)
	]

	func register(handler: @escaping (Int) -> Void) {
		self.handler = handler
		guard !handlerInstalled else {
			return
		}
		let eventTypes: [EventTypeSpec] = [
			EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
		]
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
			if (1...13).contains(index) {
				DispatchQueue.main.async {
					OptionNumberHotKeys.shared.handler?(index)
				}
			}else if (200...225).contains(index) {
				/// Option+letter -> search input (id 200 + letter index)
				let letter = String(UnicodeScalar(97 + (index - 200))!)
				DispatchQueue.main.async {
					OptionNumberHotKeys.shared.searchHandler?(letter)
				}
			}else if index == 310 {
				/// Option+0 -> search input "0"
				DispatchQueue.main.async {
					OptionNumberHotKeys.shared.searchHandler?("0")
				}
			}else if index == 320 {
				/// Option+delete -> backspace in search
				DispatchQueue.main.async {
					OptionNumberHotKeys.shared.searchHandler?("\u{08}")
				}
			}
			return noErr
		}, 1, eventTypes, nil, nil)
		guard status == noErr else {
			NSLog("[DockWidget]: Failed to install hotkey event handler: \(status)")
			return
		}
		handlerInstalled = true
		let signature = OSType(0x4F4B4544) // 'OKED'
		for (keyCode, id, modifiers) in hotKeys {
			var hotKeyRef: EventHotKeyRef?
			let hotKeyID = EventHotKeyID(signature: signature, id: UInt32(id))
			let registerStatus = RegisterEventHotKey(keyCode,
													 modifiers,
													 hotKeyID,
													 GetApplicationEventTarget(),
													 0,
													 &hotKeyRef)
			if registerStatus != noErr {
				NSLog("[DockWidget]: Failed to register hotkey for id \(id): \(registerStatus)")
			}
			hotKeyRefs.append(hotKeyRef)
		}
	}

	/// Register Option+letter / Option+0 / Option+delete while the app
	/// switcher is active. These are unregistered on exit so normal
	/// Option+letter typing (accents, shortcuts) keeps working elsewhere.
	func registerSearch(handler: @escaping (String) -> Void) {
		guard searchHotKeyRefs.isEmpty else {
			searchHandler = handler
			return
		}
		self.searchHandler = handler
		let signature = OSType(0x4F4B4544) // 'OKED'
		var newRefs: [EventHotKeyRef?] = []
		for (keyCode, letterIndex) in letterKeyCodes {
			var ref: EventHotKeyRef?
			let hotKeyID = EventHotKeyID(signature: signature, id: UInt32(200 + letterIndex))
			let status = RegisterEventHotKey(keyCode, UInt32(optionKey), hotKeyID, GetApplicationEventTarget(), 0, &ref)
			if status != noErr {
				NSLog("[DockWidget]: Failed to register search hotkey \(letterIndex): \(status)")
			}
			newRefs.append(ref)
		}
		var ref0: EventHotKeyRef?
		let id0 = EventHotKeyID(signature: signature, id: 310)
		if RegisterEventHotKey(UInt32(kVK_ANSI_0), UInt32(optionKey), id0, GetApplicationEventTarget(), 0, &ref0) != noErr {
			NSLog("[DockWidget]: Failed to register search hotkey for 0")
		}
		newRefs.append(ref0)
		var refDelete: EventHotKeyRef?
		let idDelete = EventHotKeyID(signature: signature, id: 320)
		if RegisterEventHotKey(UInt32(kVK_Delete), UInt32(optionKey), idDelete, GetApplicationEventTarget(), 0, &refDelete) != noErr {
			NSLog("[DockWidget]: Failed to register search hotkey for delete")
		}
		newRefs.append(refDelete)
		searchHotKeyRefs = newRefs
	}

	func unregisterSearch() {
		searchHandler = nil
		for ref in searchHotKeyRefs {
			if let ref = ref {
				UnregisterEventHotKey(ref)
			}
		}
		searchHotKeyRefs = []
	}

}

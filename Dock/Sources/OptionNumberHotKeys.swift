//
//  OptionNumberHotKeys.swift
//  Dock
//
//  Registers global hotkeys for the Touch Bar dock:
//    Option+1..9  -> switch to the Nth app in the dock
//    Option+[     -> shrink the dock item (icon) size
//    Option+]     -> grow the dock item (icon) size
//

import Foundation
import Carbon

final class OptionNumberHotKeys {

	static let shared = OptionNumberHotKeys()

	private var handler: ((Int) -> Void)?
	private var handlerInstalled = false
	private var hotKeyRefs: [EventHotKeyRef?] = []

	/// (keyCode, id) pairs. ids 1-9 are app switch; 10 = shrink, 11 = grow.
	private let hotKeys: [(UInt32, Int)] = [
		(UInt32(kVK_ANSI_1), 1), (UInt32(kVK_ANSI_2), 2), (UInt32(kVK_ANSI_3), 3),
		(UInt32(kVK_ANSI_4), 4), (UInt32(kVK_ANSI_5), 5), (UInt32(kVK_ANSI_6), 6),
		(UInt32(kVK_ANSI_7), 7), (UInt32(kVK_ANSI_8), 8), (UInt32(kVK_ANSI_9), 9),
		(UInt32(kVK_ANSI_LeftBracket), 10),
		(UInt32(kVK_ANSI_RightBracket), 11)
	]

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
			if (1...11).contains(index) {
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
		let signature = OSType(0x4F4B4544) // 'OKED'
		for (keyCode, id) in hotKeys {
			var hotKeyRef: EventHotKeyRef?
			let hotKeyID = EventHotKeyID(signature: signature, id: UInt32(id))
			let registerStatus = RegisterEventHotKey(keyCode,
													 UInt32(optionKey),
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

}
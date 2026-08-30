//
//  OptionNumberHotKeys.swift
//  Dock
//
//  Registers global Option+1..9 hotkeys to switch to the Nth app in the Touch Bar dock.
//

import Foundation
import Carbon

final class OptionNumberHotKeys {

	static let shared = OptionNumberHotKeys()

	private var handler: ((Int) -> Void)?
	private var handlerInstalled = false
	private var hotKeyRefs: [EventHotKeyRef?] = []

	private let keyCodes: [UInt32] = [
		UInt32(kVK_ANSI_1), UInt32(kVK_ANSI_2), UInt32(kVK_ANSI_3),
		UInt32(kVK_ANSI_4), UInt32(kVK_ANSI_5), UInt32(kVK_ANSI_6),
		UInt32(kVK_ANSI_7), UInt32(kVK_ANSI_8), UInt32(kVK_ANSI_9)
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
			if (1...9).contains(index) {
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
		for (offset, keyCode) in keyCodes.enumerated() {
			var hotKeyRef: EventHotKeyRef?
			let hotKeyID = EventHotKeyID(signature: signature, id: UInt32(offset + 1))
			let registerStatus = RegisterEventHotKey(keyCode,
													 UInt32(optionKey),
													 hotKeyID,
													 GetApplicationEventTarget(),
													 0,
													 &hotKeyRef)
			if registerStatus != noErr {
				NSLog("[DockWidget]: Failed to register hotkey for index \(offset + 1): \(registerStatus)")
			}
			hotKeyRefs.append(hotKeyRef)
		}
	}

}
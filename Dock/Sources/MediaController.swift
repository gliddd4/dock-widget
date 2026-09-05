//
//  MediaController.swift
//  Dock
//
//  Option-hold media controls: Space toggles play/pause, Left/Right switch
//  tracks, and Up/Down step the system volume by 2 (percent of full scale).
//

import Foundation
import CoreAudio

enum MediaController {

	/// NX media key types (IOKit ev_keymap.h)
	private static let nxKeyPlay: UInt32 = 16
	private static let nxKeyNext: UInt32 = 17
	private static let nxKeyPrevious: UInt32 = 18
	private static let nxKeySoundUp: UInt32 = 0
	private static let nxKeySoundDown: UInt32 = 1

	static func togglePlayPause() {
		postMediaKey(nxKeyPlay)
	}

	static func nextTrack() {
		postMediaKey(nxKeyNext)
	}

	static func previousTrack() {
		postMediaKey(nxKeyPrevious)
	}

	static func adjustVolume(by delta: Float) {
		guard let device = defaultOutputDevice() else {
			NSLog("[MediaController]: No default output device found")
			return
		}
		/// Volume may live on the master element or on the left/right
		/// channels; prefer per-channel when available (setting a master
		/// element that doesn't really exist silently does nothing)
		var channelElements: [AudioObjectPropertyElement] = []
		for element in [1, 2] as [AudioObjectPropertyElement] where isVolumeSettable(device, element) {
			channelElements.append(element)
		}
		if channelElements.isEmpty, isVolumeSettable(device, kAudioObjectPropertyElementMain) {
			channelElements = [kAudioObjectPropertyElementMain]
		}
		guard !channelElements.isEmpty else {
			/// Hardware-controlled volume: fall back to the system volume keys
			postMediaKey(delta > 0 ? nxKeySoundUp : nxKeySoundDown)
			return
		}
		var current = Float32(0)
		getVolume(device, element: channelElements[0], into: &current)
		let target = clamp(current + delta)
		for element in channelElements {
			setVolume(device, element: element, value: target)
		}
	}

	// MARK: Media key synthesis

	/// Post a synthetic media key press+release through the HID event tap
	private static func postMediaKey(_ key: UInt32) {
		for pressed in [true, false] {
			let data1 = Int(key) << 16 | (pressed ? 0xA00 : 0xB00)
			let event = NSEvent.otherEvent(with: .systemDefined,
										   location: .zero,
										   modifierFlags: NSEvent.ModifierFlags(rawValue: 0xA),
										   timestamp: 0,
										   windowNumber: 0,
										   context: nil,
										   subtype: 8,
										   data1: data1,
										   data2: -1)
			event?.cgEvent?.post(tap: .cghidEventTap)
		}
	}

	// MARK: CoreAudio volume

	private static func defaultOutputDevice() -> AudioDeviceID? {
		var deviceID = AudioDeviceID(0)
		var size = UInt32(MemoryLayout<AudioDeviceID>.size)
		var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
												 mScope: kAudioObjectPropertyScopeGlobal,
												 mElement: kAudioObjectPropertyElementMaster)
		let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
		guard status == noErr, deviceID != 0 else {
			return nil
		}
		return deviceID
	}

	private static func volumeAddress(_ element: AudioObjectPropertyElement) -> AudioObjectPropertyAddress {
		AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
								   mScope: kAudioDevicePropertyScopeOutput,
								   mElement: element)
	}

	private static func getVolume(_ device: AudioDeviceID, element: AudioObjectPropertyElement, into out: inout Float32) -> Bool {
		var address = volumeAddress(element)
		var size = UInt32(MemoryLayout<Float32>.size)
		return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &out) == noErr
	}

	private static func setVolume(_ device: AudioDeviceID, element: AudioObjectPropertyElement, value: Float32) {
		var address = volumeAddress(element)
		var value = value
		AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
	}

	private static func isVolumeSettable(_ device: AudioDeviceID, _ element: AudioObjectPropertyElement) -> Bool {
		var address = volumeAddress(element)
		var settable: DarwinBoolean = false
		let status = AudioObjectIsPropertySettable(device, &address, &settable)
		return status == noErr && settable.boolValue
	}

	private static func clamp(_ value: Float) -> Float {
		return min(1, max(0, value))
	}

}

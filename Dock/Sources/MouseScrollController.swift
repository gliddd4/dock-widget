//
//  MouseScrollController.swift
//  Dock
//
//  Option+W/S scroll mode: pressing Option+W warps the cursor to the center
//  of the foreground window; W and S then scroll up/down while Option stays
//  held. Releasing Option warps the cursor back to where it started.
//

import Foundation
import AppKit
import ApplicationServices
import Carbon

final class MouseScrollController {

	static let shared = MouseScrollController()

	private var eventTap: CFMachPort?
	private var optionWasDown = false
	private var scrollModeActive = false
	private var originalPosition: NSPoint?

	/// Returning nil from the handler swallows the event, returning it passes it on
	private static let tapCallback: CGEventTapCallBack = { _, type, event, refcon in
		guard let refcon = refcon else {
			return Unmanaged.passRetained(event)
		}
		let controller = Unmanaged<MouseScrollController>.fromOpaque(refcon).takeUnretainedValue()
		guard let passedThrough = controller.handle(type: type, event: event) else {
			return nil
		}
		return Unmanaged.passRetained(passedThrough)
	}

	func start() {
		guard eventTap == nil else { return }
		let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
		guard let tap = CGEvent.tapCreate(tap: .cghidEventTap,
										  place: .headInsertEventTap,
										  options: .defaultTap,
										  eventsOfInterest: CGEventMask(mask),
										  callback: MouseScrollController.tapCallback,
										  userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
			NSLog("[MouseScrollController]: Failed to create event tap (missing Accessibility permission?)")
			return
		}
		eventTap = tap
		CGEvent.tapEnable(tap: tap, enable: true)
		if let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) {
			CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
		}
	}

	func stop() {
		if scrollModeActive {
			exitScrollMode(restoreCursor: false)
		}
		if let tap = eventTap {
			CGEvent.tapEnable(tap: tap, enable: false)
			CFMachPortInvalidate(tap)
			eventTap = nil
		}
		optionWasDown = false
	}

	private func handle(type: CGEventType, event: CGEvent) -> CGEvent? {
		switch type {
		case .flagsChanged:
			let optionDown = event.flags.contains(.maskAlternate)
			if !optionDown && optionWasDown && scrollModeActive {
				exitScrollMode(restoreCursor: true)
			}
			optionWasDown = optionDown
			return event
		case .keyDown:
			guard event.flags.contains(.maskAlternate) else {
				return event
			}
			let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
			if keyCode == Int64(kVK_ANSI_W) {
				if !scrollModeActive {
					enterScrollMode()
				}
				if scrollModeActive {
					scroll(by: 4)
					return nil
				}
				return event
			}
			if keyCode == Int64(kVK_ANSI_S), scrollModeActive {
				scroll(by: -2)
				return nil
			}
			return event
		case .tapDisabledByTimeout, .tapDisabledByUserInput:
			if let tap = eventTap {
				CGEvent.tapEnable(tap: tap, enable: true)
			}
			return event
		default:
			return event
		}
	}

	private func enterScrollMode() {
		guard let center = frontmostWindowCenter() else { return }
		let cocoaLocation = NSEvent.mouseLocation
		let primaryHeight = NSScreen.screens.first?.frame.height ?? cocoaLocation.y
		originalPosition = NSPoint(x: cocoaLocation.x, y: primaryHeight - cocoaLocation.y)
		CGAssociateMouseAndMouseCursorPosition(0)
		CGWarpMouseCursorPosition(center)
		CGAssociateMouseAndMouseCursorPosition(1)
		scrollModeActive = true
	}

	private func exitScrollMode(restoreCursor: Bool) {
		scrollModeActive = false
		if restoreCursor, let original = originalPosition {
			CGAssociateMouseAndMouseCursorPosition(0)
			CGWarpMouseCursorPosition(original)
			CGAssociateMouseAndMouseCursorPosition(1)
		}
		originalPosition = nil
	}

	/// Center point (global display coordinates) of the frontmost app's
	/// focused window, via the Accessibility API
	private func frontmostWindowCenter() -> NSPoint? {
		guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
		let appElement = AXUIElementCreateApplication(app.processIdentifier)
		var focusedRef: CFTypeRef?
		guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedRef) == .success,
			  let focused = focusedRef, CFGetTypeID(focused) == AXUIElementGetTypeID() else {
			return nil
		}
		let window = focused as! AXUIElement
		var positionRef: CFTypeRef?
		var sizeRef: CFTypeRef?
		guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRef) == .success,
			  AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
			  let position = positionRef, let size = sizeRef else {
			return nil
		}
		var point = CGPoint.zero
		var frameSize = CGSize.zero
		AXValueGetValue(position as! AXValue, .cgPoint, &point)
		AXValueGetValue(size as! AXValue, .cgSize, &frameSize)
		guard frameSize.width > 0, frameSize.height > 0 else { return nil }
		return NSPoint(x: point.x + frameSize.width / 2, y: point.y + frameSize.height / 2)
	}

	private func scroll(by lines: CGFloat) {
		guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1,
								  wheel1: Int32(lines), wheel2: 0, wheel3: 0) else {
			return
		}
		event.post(tap: .cghidEventTap)
	}

}

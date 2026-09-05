//
//  AppDelegate.swift
//  CornerDock
//

import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {

	private var panels: [CornerPanel] = []
	private var statusItem: NSStatusItem?

	func applicationWillFinishLaunching(_ notification: Notification) {
		NSApp.setActivationPolicy(.accessory)
	}

	func applicationDidFinishLaunching(_ notification: Notification) {
		setupPanels()
		setupStatusItem()
		observeScreenChanges()
	}

	private func setupPanels() {
		panels.removeAll()
		let trash = CornerPanel(kind: .trash)
		let downloads = CornerPanel(kind: .downloads)
		trash.position(on: NSScreen.main)
		downloads.position(on: NSScreen.main)
		trash.orderFrontRegardless()
		downloads.orderFrontRegardless()
		panels = [trash, downloads]
	}

	private func observeScreenChanges() {
		NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
											   object: nil,
											   queue: .main) { [weak self] _ in
			self?.panels.forEach { $0.position(on: NSScreen.main) }
		}
	}

	// MARK: Status item

	private func setupStatusItem() {
		let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
		item.button?.title = "📦"
		let menu = NSMenu()
		menu.addItem(NSMenuItem(title: "CornerDock", action: nil, keyEquivalent: ""))

		let loginItem = NSMenuItem(title: "Open at Login", action: #selector(toggleLoginItem), keyEquivalent: "")
		loginItem.target = self
		loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
		menu.addItem(loginItem)

		menu.addItem(.separator())
		let quit = NSMenuItem(title: "Quit CornerDock", action: #selector(quit), keyEquivalent: "q")
		quit.target = self
		menu.addItem(quit)
		item.menu = menu
		statusItem = item
	}

	@objc private func toggleLoginItem() {
		do {
			switch SMAppService.mainApp.status {
			case .enabled:
				try SMAppService.mainApp.unregister()
			default:
				try SMAppService.mainApp.register()
			}
		} catch {
			NSLog("[CornerDock] login item error: \(error)")
		}
		/// Refresh the menu state
		statusItem?.menu = nil
		setupStatusItem()
	}

	@objc private func quit() {
		NSApp.terminate(nil)
	}

}

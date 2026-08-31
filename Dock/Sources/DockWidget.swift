//
//  DockWidget.swift
//  Pock
//
//  Created by Pierluigi Galdi on 06/04/2019.
//  Copyright © 2019 Pierluigi Galdi. All rights reserved.
//

import Foundation
import PockKit
import TinyConstraints
import ApplicationServices

/// A single cheat-sheet row. Draws a native-style selection pill behind
/// the frontmost app's row (matches the highlight Apple uses in menus).
/// Mirror of the open-source Snap launcher's result row: a flat, full-width
/// solid highlight (#FF79C6) behind the selected app, exactly as Snap draws it.
private final class CheatSheetRowView: NSView {
	var highlighted: Bool = false {
		didSet { needsDisplay = true }
	}
	init(highlighted: Bool) {
		super.init(frame: .zero)
		self.highlighted = highlighted
		wantsLayer = true
	}
	override init(frame: NSRect) {
		super.init(frame: frame)
		wantsLayer = true
	}
	required init?(coder: NSCoder) {
		super.init(coder: coder)
		wantsLayer = true
	}
	override func draw(_ dirtyRect: NSRect) {
		super.draw(dirtyRect)
		guard highlighted else { return }
		let c = NSColor(calibratedRed: 0xFF / 255.0, green: 0x79 / 255.0, blue: 0xC6 / 255.0, alpha: 1)
		c.setFill()
		bounds.fill()
	}
}

class DockWidget: NSObject, PKWidget, PKScreenEdgeMouseDelegate {
	
	static var identifier: String = "DockWidget"
	var customizationLabel: String = "Dock"
	var view: NSView!
	
	/// Core
	private var dockRepository: 	  DockRepository!
	private var dropDispatchWorkItem: DispatchWorkItem?
	
	/// UI
	private var stackView:          NSStackView! = NSStackView(frame: .zero)
	private var dockScrubber:       NSScrubber!  = NSScrubber(frame: NSRect(x: 0, y: 0, width: 200, height: Constants.dockItemSize.height))
	private var separator:          NSView! 	 = NSView(frame:     NSRect(x: 0, y: 0, width: 1, 	height: 20))
	private var persistentScrubber: NSScrubber!  = NSScrubber(frame: NSRect(x: 0, y: 0, width: 50, 	height: Constants.dockItemSize.height))
	
	private var persistentScrubberWidthConstraint: NSLayoutConstraint {
		if let previous = persistentScrubber.constraints.first(where: { $0.identifier == "persistentScrubber.width" }) {
			return previous
		} else {
			let constraint = persistentScrubber.width(0)
			constraint.identifier = "persistentScrubber.width"
			constraint.isActive = true
			return constraint
		}
	}
	
	/// Data
	private var dockItems:       [DockItem] = []
	private var persistentItems: [DockItem] = []
	private var cachedDockItemViews: 	   [DockItemView] = []
	private var cachedPersistentItemViews: [DockItemView] = []
	private var itemViewWithMouseOver: 	  DockItemView?
	private var itemViewWithDraggingOver: DockItemView?
	/// Frontmost tracking for the box + name reveal
	private var frontmostIndex: Int?

	/// Apps we minimized via tap-to-toggle, so restore works even when
	/// "minimize into application icon" hides windows from the AX list.
	private var minimizedAppIdentifiers: Set<String> = []

	// MARK: Option-hold hotkey cheat sheet
	private var optionMonitor: Any?
	private var optionPanel: NSPanel?

	/// Current adjustable dock item height (icon grows via the adaptive constraints)
	private var currentItemHeight: CGFloat {
		get {
			let saved = UserDefaults.standard.double(forKey: Constants.calibrationItemHeightKey)
			return saved > 0 ? CGFloat(saved) : Constants.dockItemSize.height
		}
		set {
			UserDefaults.standard.set(Double(newValue), forKey: Constants.calibrationItemHeightKey)
		}
	}

	/// Current vertical offset of the dock items (moves them up/down within the bar)
	private var currentItemYOffset: CGFloat {
		get {
			let saved = UserDefaults.standard.double(forKey: Constants.calibrationItemYOffsetKey)
			return saved != 0 ? CGFloat(saved) : Constants.dockItemYOffsetDefault
		}
		set {
			UserDefaults.standard.set(Double(newValue), forKey: Constants.calibrationItemYOffsetKey)
		}
	}
	
	var imageForCustomization: NSImage {
		return Bundle(for: DockWidget.self).image(forResource: "WidgetPreview")!
	}
	
	override required init() {
		super.init()
		self.configureStackView()
		self.view = stackView
	}
	
	func initialize() {
		self.configureStackView()
		self.configureDockScrubber()
		self.configureSeparator()
		self.configurePersistentScrubber()
		self.displayScrubbers()
		self.view = stackView
		self.dockRepository = DockRepository(delegate: self)
		NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(displayScrubbers),
														  name: .shouldReloadPersistentItems, object: nil)
		NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(reloadScrubbersLayout),
														  name: .shouldReloadScrubbersLayout, object: nil)
		NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(deepReload(_:)),
														  name: .shouldReloadDock, object: nil)
		/// Hide System Dock if needed
		if let hideSystemDock: Bool = Preferences[.hideSystemDock] {
			if hideSystemDock && DockHelper.currentMode != .disabled {
				/// Fully hide the dock (autohide with an enormous delay) so apps get the full screen
				DockHelper.setDockMode(.disabled)
			}
		}else {
			if DockHelper.currentMode == .disabled {
				Preferences[.hideSystemDock] = true
				DockHelper.setDockMode(.disabled)
			}
		}
		/// Register Option+1..9 hotkeys for app switching, plus Option+[/] to resize
		OptionNumberHotKeys.shared.register { [weak self] index in
			self?.handleHotKey(index)
		}
		/// Watch for the Option key being held: show the numbered app cheat sheet
		self.optionMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
			let optionDown = event.modifierFlags.contains(.option)
			DispatchQueue.main.async {
				self?.setOptionPanelVisible(optionDown)
			}
		}
	}

	/// Activate the Nth app in the Touch Bar dock (0-based)
	private func activateItem(at index: Int) {
		guard index >= 0, index < dockItems.count else {
			return
		}
		launchItem(dockItems[index])
	}

	/// Route Option hotkeys. 1-9 = app switch, 10 = shrink, 11 = grow.
	private func handleHotKey(_ index: Int) {
		switch index {
		case 1...9:
			activateItem(at: index - 1)
		case 10:
			adjustItemHeight(by: -1)
		case 11:
			adjustItemHeight(by: 1)
		case 12:
			adjustItemYOffset(by: 1)   // "{" : move up
		case 13:
			adjustItemYOffset(by: -1)  // "}" : move down
		default:
			break
		}
	}

	/// Grow/shrink the dock item height by `delta` points and re-layout live.
	private func adjustItemHeight(by delta: CGFloat) {
		let newHeight = min(max(currentItemHeight + delta, 20), 48)
		currentItemHeight = newHeight
		NSLog("[DockWidget] calibration item height set to %.0f", newHeight)
		dockScrubber.frame.size.height = newHeight
		dockScrubber.scrubberLayout = makeDockLayout()
		dockScrubber.reloadData()
		/// Force the cached item views to re-resolve their adaptive icon constraints
		/// so the icons actually grow with the taller item.
		dockScrubber.layoutSubtreeIfNeeded()
		cachedDockItemViews.forEach { $0.layoutSubtreeIfNeeded() }
	}

	/// Move the dock items vertically by `delta` points within the bar.
	private func adjustItemYOffset(by delta: CGFloat) {
		let newOffset = max(min(currentItemYOffset + delta, 20), -20)
		currentItemYOffset = newOffset
		NSLog("[DockWidget] calibration item y offset set to %.0f", newOffset)
		dockScrubber.scrubberLayout = makeDockLayout()
		dockScrubber.reloadData()
	}
	
	func viewDidAppear() {
		initialize()
		/// Make the scrubber fill the widget view's actual height so icons never clip
		DispatchQueue.main.async { [weak self] in
			guard let self = self else { return }
			self.dockScrubber.frame.size.height = self.stackView.bounds.height
			NSLog("[DockWidget] widget height: %.1f scrubber: %.1f itemSize: %.1f",
				  self.stackView.bounds.height, self.dockScrubber.frame.height, Constants.dockItemSize.height)
			self.dockScrubber.scrubberLayout = self.makeDockLayout()
			self.dockScrubber.reloadData()
		}
	}
	
	func viewDidDisappear() {
		hideOptionPanel()
		if let monitor = optionMonitor {
			NSEvent.removeMonitor(monitor)
			optionMonitor = nil
		}
		deepReload(nil)
		itemViewWithMouseOver = nil
		NSWorkspace.shared.notificationCenter.removeObserver(self)
	}
	
	@objc private func deepReload(_ notification: NSNotification?) {
		self.dockItems.removeAll()
		self.persistentItems.removeAll()
		self.cachedDockItemViews.removeAll()
		self.cachedPersistentItemViews.removeAll()
		self.frontmostIndex = nil
		self.dockScrubber.reloadData()
		self.persistentScrubber.reloadData()
		if notification == nil {
			return
		}
		self.dockRepository = DockRepository(delegate: self)
		print("[DockWidget]: DEEP RELOAD")
	}
	
	/// Configure stack view
	private func configureStackView() {
		stackView.alignment = .centerY
		stackView.orientation = .horizontal
		stackView.distribution = .fill
	}
	
	@objc private func displayScrubbers() {
		/// Persistent items (Downloads, Trash, folders) are intentionally never shown
		self.separator.isHidden          = true
		self.persistentScrubber.isHidden = true
	}

	@objc private func reloadScrubbersLayout() {
		cachedDockItemViews.removeAll()
		dockScrubber.scrubberLayout = makeDockLayout()
		dockScrubber.reloadData()
		cachedPersistentItemViews.removeAll()
		let persistentLayout              = NSScrubberFlowLayout()
		persistentLayout.itemSize         = Constants.dockItemSize
		persistentLayout.itemSpacing      = Preferences[.itemSpacing]
		persistentScrubber.scrubberLayout = persistentLayout
		persistentScrubber.reloadData()
	}

	/// Build a variable-width layout that gives the frontmost item room for its name
	private func makeDockLayout() -> DockScrubberLayout {
		let layout = DockScrubberLayout()
		let itemSize = NSSize(width: currentItemHeight + 2, height: currentItemHeight)
		layout.itemSize    = itemSize
		layout.itemSpacing = Preferences[.itemSpacing]
		layout.itemYOffset = currentItemYOffset
		layout.frontmostIndex = frontmostIndex
		layout.nameWidthProvider = { [weak self] index in
			guard let self = self, index < self.dockItems.count, let name = self.dockItems[index].name else {
				return 0
			}
			let field = NSTextField(labelWithString: name)
			field.font = NSFont.systemFont(ofSize: Constants.nameFontSize, weight: .medium)
			let size = field.sizeThatFits(NSSize(width: Constants.nameMaxWidth, height: Constants.dockItemSize.height))
			return ceil(size.width)
		}
		return layout
	}

	/// Configure dock scrubber
	private func configureDockScrubber() {
		dockScrubber.dataSource = self
		dockScrubber.delegate = self
		dockScrubber.showsAdditionalContentIndicators = true
		dockScrubber.mode = .free
		dockScrubber.isContinuous = false
		dockScrubber.itemAlignment = .none
		dockScrubber.scrubberLayout = makeDockLayout()
		stackView.addArrangedSubview(dockScrubber)
	}

	/// Configure separator
	private func configureSeparator() {
		separator.wantsLayer = true
		separator.layer?.backgroundColor = NSColor.darkGray.cgColor
		separator.width(1)
		separator.height(20)
		/// Separator and persistent scrubber are intentionally never added to the stack view
	}
	
	/// Configure persistent scrubber
	private func configurePersistentScrubber() {
		let layout = NSScrubberFlowLayout()
		layout.itemSize    = Constants.dockItemSize
		layout.itemSpacing = Preferences[.itemSpacing]
		persistentScrubber.dataSource = self
		persistentScrubber.delegate = self
		persistentScrubber.showsAdditionalContentIndicators = true
		persistentScrubber.mode = .free
		persistentScrubber.isContinuous = false
		persistentScrubber.itemAlignment = .none
		persistentScrubber.scrubberLayout = layout
		persistentScrubberWidthConstraint.constant = (Constants.dockItemSize.width + 8) * CGFloat(min(persistentItems.count, 3))
		/// persistentScrubber is intentionally never added to the stack view
	}
	
	// MARK: Option-hold hotkey cheat sheet

	/// Show/hide a floating cheat sheet on the main screen that lists the dock
	/// apps with their Option+number hotkey, so the user knows what to press
	/// when the Touch Bar isn't visible.
	private func setOptionPanelVisible(_ visible: Bool) {
		if visible {
			showOptionPanel()
		}else {
			hideOptionPanel()
		}
	}

	private func showOptionPanel() {
		guard optionPanel == nil, !dockItems.isEmpty else { return }

		let activeBundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

		// Exact palette + metrics from the open-source Snap launcher:
		// background #282A36, text #F8F8F2, highlight #FF79C6, Menlo 18,
		// 70pt rows, 50pt icons, flat rectangle window (no rounding/shadow).
		let bgColor   = NSColor(calibratedRed: 0x28 / 255.0, green: 0x2A / 255.0, blue: 0x36 / 255.0, alpha: 1)
		let textColor = NSColor(calibratedRed: 0xF8 / 255.0, green: 0xF8 / 255.0, blue: 0xF2 / 255.0, alpha: 1)
		let font = NSFont(name: "Menlo", size: 18) ?? NSFont.systemFont(ofSize: 18)

		let rowHeight:  CGFloat = 70   // Snap resultItemHeight
		let iconSize:   CGFloat = 50   // Snap iconSizeWidth/Height
		let rowInset:   CGFloat = 12   // Snap row .padding() (leading/trailing)
		let gap:        CGFloat = 14
		let keyCol:     CGFloat = 40

		/// Measure the widest name so the panel hugs its content (capped).
		var maxNameWidth: CGFloat = 0
		for item in dockItems {
			let w = (item.name as NSString?)?.size(withAttributes: [.font: font]).width ?? 0
			maxNameWidth = max(maxNameWidth, w)
		}
		let nameCap: CGFloat = 200
		let contentWidth = rowInset + iconSize + gap + min(maxNameWidth, nameCap) + gap + keyCol + rowInset

		let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: contentWidth, height: 200),
							styleMask: [.borderless, .nonactivatingPanel],
							backing: .buffered, defer: false)
		panel.level = .floating
		panel.isOpaque = true
		panel.backgroundColor = bgColor
		panel.hasShadow = false
		panel.hidesOnDeactivate = false
		panel.isReleasedWhenClosed = false
		panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

		let container = NSView(frame: NSRect(x: 0, y: 0, width: contentWidth, height: 200))
		panel.contentView = container

		/// One full-width row per app (same order as the Touch Bar dock).
		let stack = NSStackView()
		stack.orientation = .vertical
		stack.alignment = .leading
		stack.spacing = 0
		stack.translatesAutoresizingMaskIntoConstraints = false
		container.addSubview(stack)
		NSLayoutConstraint.activate([
			stack.topAnchor.constraint(equalTo: container.topAnchor),
			stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
			stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
			stack.bottomAnchor.constraint(equalTo: container.bottomAnchor)
		])

		for (index, item) in dockItems.enumerated() {
			let isActive = item.bundleIdentifier == activeBundleId
			let isRunning = item.isRunning

			let row = CheatSheetRowView(highlighted: isActive)
			row.translatesAutoresizingMaskIntoConstraints = false
			row.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true
			row.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true

			let inner = NSStackView()
			inner.orientation = .horizontal
			inner.alignment = .centerY
			inner.spacing = 0
			inner.translatesAutoresizingMaskIntoConstraints = false
			row.addSubview(inner)
			NSLayoutConstraint.activate([
				inner.topAnchor.constraint(equalTo: row.topAnchor),
				inner.bottomAnchor.constraint(equalTo: row.bottomAnchor),
				inner.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: rowInset),
				inner.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -rowInset)
			])

			let iconView = NSImageView()
			iconView.image = item.icon
			iconView.imageScaling = .scaleProportionallyUpOrDown
			iconView.alphaValue = isRunning ? 1.0 : 0.45
			iconView.widthAnchor.constraint(equalToConstant: iconSize).isActive = true
			iconView.heightAnchor.constraint(equalToConstant: iconSize).isActive = true

			let nameLabel = NSTextField(labelWithString: item.name ?? "")
			nameLabel.font = font
			nameLabel.textColor = textColor
			nameLabel.alphaValue = isRunning ? 1.0 : 0.45
			nameLabel.lineBreakMode = .byTruncatingTail

			/// Trailing hotkey number in the same Menlo 18 as Snap's row text.
			let keyLabel = NSTextField(labelWithString: index < 9 ? "\(index + 1)" : " ")
			keyLabel.font = font
			keyLabel.textColor = textColor
			keyLabel.alphaValue = isRunning ? 1.0 : (isActive ? 1.0 : 0.6)
			keyLabel.alignment = .right

			inner.addArrangedSubview(iconView)
			let iconGap = NSView(); iconGap.translatesAutoresizingMaskIntoConstraints = false
			iconGap.widthAnchor.constraint(equalToConstant: gap).isActive = true
			inner.addArrangedSubview(iconGap)
			inner.addArrangedSubview(nameLabel)

			let spacer = NSView()
			spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
			inner.addArrangedSubview(spacer)

			let keyGap = NSView(); keyGap.translatesAutoresizingMaskIntoConstraints = false
			keyGap.widthAnchor.constraint(equalToConstant: gap).isActive = true
			inner.addArrangedSubview(keyGap)

			let keyWrap = NSView()
			keyWrap.translatesAutoresizingMaskIntoConstraints = false
			keyWrap.widthAnchor.constraint(equalToConstant: keyCol).isActive = true
			keyLabel.translatesAutoresizingMaskIntoConstraints = false
			keyWrap.addSubview(keyLabel)
			NSLayoutConstraint.activate([
				keyLabel.centerYAnchor.constraint(equalTo: keyWrap.centerYAnchor),
				keyLabel.trailingAnchor.constraint(equalTo: keyWrap.trailingAnchor)
			])
			inner.addArrangedSubview(keyWrap)

			stack.addArrangedSubview(row)
		}

		/// Size the panel to fit its rows (capped so it never covers the screen).
		let height = min(CGFloat(dockItems.count) * rowHeight, 600)
		panel.setContentSize(NSSize(width: contentWidth, height: max(height, rowHeight)))
		panel.center()
		optionPanel = panel
		panel.orderFrontRegardless()
		NSLog("[DockWidget] option cheat sheet shown (%d apps)", dockItems.count)
	}

	private func hideOptionPanel() {
		optionPanel?.orderOut(nil)
		optionPanel = nil
	}

	// MARK: ScreenEdgeMouseDelegate (Select, Scroll & Drag)
	func screenEdgeController(_ controller: PKScreenEdgeController, mouseEnteredAtLocation location: NSPoint, in view: NSView) {
		updateCursorLocation(location, in: view)
	}
	
	func screenEdgeController(_ controller: PKScreenEdgeController, mouseExitedAtLocation location: NSPoint, in view: NSView) {
		itemViewWithMouseOver?.set(isMouseOver: false)
	}
	
	func screenEdgeController(_ controller: PKScreenEdgeController, mouseMovedAtLocation location: NSPoint, in view: NSView) {
		updateCursorLocation(location, in: view)
	}
	
	func screenEdgeController(_ controller: PKScreenEdgeController, mouseScrollWithDelta delta: CGFloat, atLocation location: NSPoint, in view: NSView) {
		itemViewWithMouseOver?.set(isMouseOver: false)
		guard let scrubber = scrubber(at: location, in: view) else {
			return
		}
		scrubber.scroll(with: delta)
	}
	
	func screenEdgeController(_ controller: PKScreenEdgeController, mouseClickAtLocation location: NSPoint, in view: NSView) {
		itemViewWithMouseOver?.set(isMouseOver: false)
		launchItem(item(at: location, in: view))
	}
	
	 func screenEdgeController(_ controller: PKScreenEdgeController, draggingEntered info: NSDraggingInfo, filepath: String, in view: NSView) -> NSDragOperation {
		itemViewWithMouseOver?.set(isMouseOver: false)
		return .every
	}
	
	func screenEdgeController(_ controller: PKScreenEdgeController, draggingUpdated info: NSDraggingInfo, filepath: String, in view: NSView) -> NSDragOperation {
		let location = info.draggingLocation
		let item = self.item(at: location, in: view)
		if let item = item, item.isRunning, let itemView = itemView(at: location, in: view) {
			if dropDispatchWorkItem == nil {
				dropDispatchWorkItem = DispatchWorkItem { [weak self, item, itemView] in
					if self?.itemViewWithDraggingOver == itemView {
						NSLog("[DockWidget]: Ready to launch: `\(item.bundleIdentifier ?? "unknown")`")
						self?.launchItem(item)
					}
				}
				DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: dropDispatchWorkItem!)
			}
			itemViewWithDraggingOver = itemView
		}else {
			if itemViewWithDraggingOver != nil {
				itemViewWithDraggingOver = nil
				dropDispatchWorkItem?.cancel()
				dropDispatchWorkItem  = nil
			}
		}
		updateCursorLocation(location, in: view)
		return .every
	}
	
	func screenEdgeController(_ controller: PKScreenEdgeController, performDragOperation info: NSDraggingInfo, filepath: String, in view: NSView) -> Bool {
		guard let item = item(at: info.draggingLocation, in: view) else {
			return false
		}
		let filePathURL = URL(fileURLWithPath: filepath)
		if let bundleIdentifier = item.bundleIdentifier {
			return NSWorkspace.shared.open([filePathURL], withAppBundleIdentifier: bundleIdentifier, options: .withErrorPresentation, additionalEventParamDescriptor: nil, launchIdentifiers: nil)
		}else if let destinationPathURL = item.path?.appendingPathComponent(filePathURL.lastPathComponent) {
			do {
				if item.path?.relativePath == Constants.trashPath {
					try FileManager.default.trashItem(at: filePathURL, resultingItemURL: nil)
					persistentScrubber?.reloadData()
					SystemSound.play(.move_to_trash)
				}else {
					try FileManager.default.moveItem(at: filePathURL, to: destinationPathURL)
					SystemSound.play(.volume_mount)
				}
				return true
			}catch {
				print("[DockWidget][mv] Error: \(error.localizedDescription)")
				NSSound.beep()
				return false
			}
		}
		return false
	}
	
	private func updateCursorLocation(_ location: NSPoint?, in view: NSView) {
		itemViewWithMouseOver?.set(isMouseOver: false)
		itemViewWithMouseOver = nil
		guard let location = location else {
			return
		}
		itemViewWithMouseOver?.set(isMouseOver: false)
		itemViewWithMouseOver = itemView(at: location, in: view)
		itemViewWithMouseOver?.set(isMouseOver: true)
	}
	
}

extension DockWidget: DockDelegate {

	func didUpdateDockItem(_ item: DockItem, at index: Int, terminated: Bool, isDefaults: Bool) {
		DispatchQueue.main.async { [weak self, item] in
			guard let self = self else {
				return
			}
			if let itemView = self.itemView(for: item) {
				if let currentIndex = self.dockItems.firstIndex(where: { $0.bundleIdentifier == item.bundleIdentifier }) {
					if terminated && !isDefaults {
						self.dockItems.remove(at: currentIndex)
						self.dockScrubber.removeItems(at: IndexSet(integer: currentIndex))
						if let cachedViewIndex = self.cachedDockItemViews.firstIndex(where: { $0.diffId == item.diffId }) {
							self.cachedDockItemViews.remove(at: cachedViewIndex)
						}
					}else {
						itemView.set(isRunning:   item.isRunning)
						itemView.set(isFrontmost: self.frontmostIndex.map { self.dockItems[$0].diffId } == item.diffId)
						itemView.set(isLaunching: item.isLaunching)
						self.dockScrubber.reloadItems(at: IndexSet(integer: currentIndex))
					}
				}
			}else {
				if self.dockItems.contains(item) == false {
					if index < self.dockItems.count {
						self.dockItems.remove(at: index)
						self.dockItems.insert(item, at: index)
						self.dockScrubber.reloadItems(at: IndexSet(integer: index))
					}else {
						let validIndex = self.dockItems.count
						self.dockItems.append(item)
						self.dockScrubber.insertItems(at: IndexSet(integer: validIndex))
						self.dockScrubber.animator().scrollItem(at: validIndex, to: .center)
					}
				}else {
					self.dockScrubber.reloadData()
				}
			}
			/// Do another check because of a bug in `NSScrubber`
			if self.dockScrubber.numberOfItems != self.dockItems.count {
				self.dockScrubber.reloadData()
			}else {
				if terminated && !isDefaults {
					for (index,item) in self.dockItems.enumerated() {
						self.updateView(for: item, isPersistent: item.isPersistentItem)
						self.dockScrubber.reloadItems(at: IndexSet(integer: index))
					}
				}
			}
			self.reorderRunningAppsFirst()
			self.syncFrontmostIfNeeded()
		}
	}
	
	func didUpdateActiveItem(_ item: DockItem, at index: Int, activated: Bool) {
		DispatchQueue.main.async { [weak self] in
			guard let self = self else {
				return
			}
			/// Resolve the item's *current* index by identity — the repository's
			/// `index` refers to its (un-reordered) dock order, which diverges from
			/// our running-first ordering. Using that stale index highlights the wrong
			/// item and reveals the wrong name.
			guard let currentIndex = self.dockItems.firstIndex(where: { $0.diffId == item.diffId }) else {
				return
			}
			if activated {
				self.applyFrontmost(currentIndex)
			}else {
				/// Deactivated: clear the highlight if this was the frontmost item
				if self.frontmostIndex == currentIndex {
					self.applyFrontmost(nil)
				}
			}
			self.dockScrubber.scrubberLayout = self.makeDockLayout()
			self.dockScrubber.reloadData()
			if let index = self.frontmostIndex {
				self.dockScrubber.animator().scrollItem(at: index, to: .center)
			}
		}
	}
	
	func didUpdateBadge(for apps: [DockItem]) {
		DispatchQueue.main.async { [weak self] in
			guard let s = self else { return }
			s.cachedDockItemViews.forEach({ view in
				view.set(hasBadge: apps.first(where: { $0.diffId == view.diffId })?.hasBadge ?? false)
			})
		}
	}
	
	func didUpdatePersistentItem(_ item: DockItem, at index: Int, added: Bool) {
		DispatchQueue.main.async { [weak self, item] in
			guard let self = self else {
				return
			}
			if let itemIndex = self.persistentItems.firstIndex(where: { $0.path == item.path }), let itemView = self.itemView(for: item) {
				if added {
					itemView.set(icon: item.icon)
					self.persistentScrubber.reloadItems(at: IndexSet(integer: itemIndex))
				}else {
					self.persistentScrubber.removeItems(at: IndexSet(integer: itemIndex))
					self.persistentItems.remove(at: itemIndex)
					if let index = self.cachedPersistentItemViews.firstIndex(where: { $0.diffId == item.diffId }) {
						self.cachedPersistentItemViews.remove(at: index)
					}
				}
			}else {
				self.persistentItems.insert(item, at: index)
				self.persistentScrubber.insertItems(at: IndexSet(integer: index))
			}
			self.displayScrubbers()
			self.persistentScrubberWidthConstraint.constant = (Constants.dockItemSize.width + 8) * CGFloat(min(self.persistentItems.count, 3))
		}
	}
	
	@discardableResult
	private func updateView(for item: DockItem?, isPersistent: Bool) -> DockItemView? {
		guard let item = item else {
			return nil
		}
		var view: DockItemView! = {
			return cachedDockItemViews.first(where: { $0.diffId == item.diffId }) ?? cachedPersistentItemViews.first(where: { $0.diffId == item.diffId })
		}()
		if view == nil {
			view = DockItemView(frame: .zero)
			if isPersistent {
				cachedPersistentItemViews.append(view)
			}else {
				cachedDockItemViews.append(view)
			}
		}
		view.diffId = item.diffId
		view.clear()
		view.set(icon:        item.icon)
		view.set(name:        item.name)
		view.set(hasBadge:    item.hasBadge)
		view.set(isRunning:   item.isRunning)
		view.set(isFrontmost: frontmostIndex.map { dockItems[$0].diffId } == item.diffId)
		return view
	}

	/// Move running apps to the left while keeping their relative dock order
	/// (stable partition: running first, then closed apps in original order)
	private func reorderRunningAppsFirst() {
		let running = dockItems.filter { $0.isRunning }
		let closed  = dockItems.filter { !$0.isRunning }
		guard running.count > 0, closed.count > 0 else {
			return
		}
		/// Remap frontmostIndex so it follows the same app after reordering
		if let frontmostIndex = frontmostIndex, frontmostIndex < dockItems.count {
			let frontmostDiffId = dockItems[frontmostIndex].diffId
			self.frontmostIndex = running.firstIndex(where: { $0.diffId == frontmostDiffId }) ??
				closed.firstIndex(where: { $0.diffId == frontmostDiffId }).map { running.count + $0 }
		}
		dockItems = running + closed
		dockScrubber.scrubberLayout = makeDockLayout()
		dockScrubber.reloadData()
	}

	/// Single source of truth for the frontmost highlight: clears every other
	/// item first so only one name is ever revealed at a time
	private func applyFrontmost(_ index: Int?) {
		frontmostIndex = index
		(cachedDockItemViews + cachedPersistentItemViews).forEach { $0.set(isFrontmost: false) }
		if let index = index, index < dockItems.count {
			itemView(for: dockItems[index])?.set(isFrontmost: true)
		}
	}

	/// Track the frontmost app once the initial items are loaded
	private func syncFrontmostIfNeeded() {
		guard frontmostIndex == nil, let index = dockItems.firstIndex(where: { $0.isFrontmost }) else {
			return
		}
		applyFrontmost(index)
		dockScrubber.scrubberLayout = makeDockLayout()
		dockScrubber.reloadData()
	}

}

extension DockWidget: NSScrubberDataSource {
	func numberOfItems(for scrubber: NSScrubber) -> Int {
		if scrubber == persistentScrubber {
			return persistentItems.count
		}
		return dockItems.count
	}
	
	func scrubber(_ scrubber: NSScrubber, viewForItemAt index: Int) -> NSScrubberItemView {
		let isPersistent = scrubber == persistentScrubber
		let item = isPersistent ? persistentItems[index] : dockItems[index]
		return updateView(for: item, isPersistent: isPersistent)!
	}
}

extension DockWidget: NSScrubberDelegate {
	
	func scrubber(_ scrubber: NSScrubber, didSelectItemAt selectedIndex: Int) {
		let item = scrubber == persistentScrubber ? persistentItems[selectedIndex] : dockItems[selectedIndex]
		launchItem(item)
		scrubber.selectedIndex = -1
	}
	
	func didBeginInteracting(with scrubber: NSScrubber) {
		itemViewWithMouseOver?.set(isMouseOver: false)
		itemViewWithMouseOver = nil
	}
	
	func launchItem(_ item: DockItem?) {
		guard let item = item else {
			return
		}
		/// Tapping a running app toggles it: if a frontmost window is showing,
		/// minimize it (yellow traffic-light); if its window is minimized,
		/// restore it. Otherwise just bring it forward normally.
		/// Prefer the real frontmost app over the tracked index so the toggle
		/// stays correct even when index tracking drifts (reorders/removals).
		let indexIsFrontmost = frontmostIndex.map { index in
			index < dockItems.count ? dockItems[index].diffId == item.diffId : false
		} ?? false
		let appIsFrontmost = item.bundleIdentifier != nil &&
			NSWorkspace.shared.frontmostApplication?.bundleIdentifier == item.bundleIdentifier
		let isFrontmost = indexIsFrontmost || appIsFrontmost
		if item.isRunning, !item.isPersistentItem, item.bundleIdentifier != Constants.kLaunchpadIdentifier,
		   let app = NSRunningApplication.runningApplications(withBundleIdentifier: item.bundleIdentifier ?? "").first {
			/// We remember which apps we minimized, because reading the AX minimized
			/// state back can fail when "minimize to application icon" hides the
			/// window from the AX windows list. Drop-out-of-our-list externally.
			let wasMinimizedHere = minimizedAppIdentifiers.remove(item.bundleIdentifier ?? "") != nil
			/// If the app has no visible window, every one of its windows is
			/// minimized (possibly into the app icon, which AX drops from its
			/// windows list) — restore it.
			if wasMinimizedHere || !hasVisibleWindow(app) {
				restoreApp(bundleIdentifier: item.bundleIdentifier)
				return
			}
			if isFrontmost {
				minimizeApp(bundleIdentifier: item.bundleIdentifier)
				return
			}
		}
		if !item.isPersistentItem, !item.isRunning, item.bundleIdentifier != Constants.kLaunchpadIdentifier, let itemView = itemView(for: item) {
			itemView.set(isLaunching: true)
		}
		dockRepository.launch(item: item, completion: { _ in })
	}

	/// Whether the app currently has at least one visible (non-minimized)
	/// window. "Minimize into application icon" removes the minimized window
	/// from the AX windows list entirely, so an empty list counts as "all
	/// minimized" and the toggle must restore instead of minimize.
	private func hasVisibleWindow(_ app: NSRunningApplication) -> Bool {
		let appElement = AXUIElementCreateApplication(app.processIdentifier)
		guard let windows = copyAttribute(appElement, kAXWindowsAttribute as CFString) as? [AXUIElement],
			  !windows.isEmpty else {
			return false
		}
		for window in windows {
			if let minimized = copyAttribute(window, kAXMinimizedAttribute as CFString) as? NSNumber, minimized.boolValue == false {
				return true
			}
		}
		return false
	}

	/// Restore (unminimize) every minimized window of the app and bring it forward.
	private func restoreApp(bundleIdentifier: String?) {
		guard let bundleIdentifier = bundleIdentifier,
			  let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first else {
			return
		}
		let appElement = AXUIElementCreateApplication(app.processIdentifier)
		/// Restore minimized windows from the AX minimized-windows list first:
		/// it includes windows minimized into the application icon, which are
		/// absent from the regular AX windows list.
		var minimizedRef: CFTypeRef?
		/// "AXMinimizedWindows" isn't exposed as a Swift constant, so use the literal.
		if AXUIElementCopyAttributeValue(appElement, "AXMinimizedWindows" as CFString, &minimizedRef) == .success,
		   let minimizedWindows = minimizedRef as? [AXUIElement] {
			for window in minimizedWindows {
				AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse as CFTypeRef)
			}
		}
		/// Also unminimize any window still visible to the regular AX windows list.
		if let windows = copyAttribute(appElement, kAXWindowsAttribute as CFString) as? [AXUIElement] {
			for window in windows {
				if let minimized = copyAttribute(window, kAXMinimizedAttribute as CFString) as? NSNumber, minimized.boolValue {
					AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse as CFTypeRef)
				}
			}
		}
		app.unhide()
		app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
	}

	/// Minimize the frontmost window of the given app (yellow traffic-light).
	/// Uses the Accessibility API, so Pock needs Accessibility permission.
	private func minimizeApp(bundleIdentifier: String?) {
		guard let bundleIdentifier = bundleIdentifier,
			  let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first else {
			return
		}
		let appElement = AXUIElementCreateApplication(app.processIdentifier)
		guard let target = minimizeTargetWindow(appElement) else {
			return
		}
		var minimizedRef: CFTypeRef?
		if AXUIElementCopyAttributeValue(target, kAXMinimizedAttribute as CFString, &minimizedRef) == .success,
		   let alreadyMinimized = minimizedRef as? NSNumber, alreadyMinimized.boolValue {
			return
		}
		if AXUIElementSetAttributeValue(target, kAXMinimizedAttribute as CFString, kCFBooleanTrue as CFTypeRef) == .success {
			minimizedAppIdentifiers.insert(bundleIdentifier)
		}
	}

	/// Return the app's focused window when available, else its first (non-minimized) window.
	/// CoreFoundation types can't be conditionally downcast with `as?`, so we check
	/// the CF type ID and then force-cast (safe once the type ID matches).
	private func minimizeTargetWindow(_ appElement: AXUIElement) -> AXUIElement? {
		if let value = copyAttribute(appElement, kAXFocusedWindowAttribute as CFString),
		   CFGetTypeID(value) == AXUIElementGetTypeID() {
			return value as! AXUIElement
		}
		if let windows = copyAttribute(appElement, kAXWindowsAttribute as CFString) as? [AXUIElement] {
			for window in windows {
				if let minimized = copyAttribute(window, kAXMinimizedAttribute as CFString) as? NSNumber, minimized.boolValue {
					continue
				}
				return window
			}
		}
		return nil
	}

	private func copyAttribute(_ element: AXUIElement, _ attribute: CFString) -> CFTypeRef? {
		var value: CFTypeRef?
		guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
			return nil
		}
		return value
	}
}

// MARK: Retrieve DockItem & DockItemView
extension DockWidget {
	private func scrubber(at location: NSPoint?, in view: NSView) -> NSScrubber? {
		guard let location = location else {
			return nil
		}
		if dockScrubber.convert(dockScrubber.bounds, to: view).contains(location) {
			return dockScrubber
		}
		if persistentScrubber.convert(persistentScrubber.bounds, to: view).contains(location) {
			return persistentScrubber
		}
		return nil
	}
	
	private func item(at location: NSPoint, in view: NSView) -> DockItem? {
		guard let itemView = itemView(at: location, in: view) else {
			return nil
		}
		return dockItems.first(where: { $0.diffId == itemView.diffId }) ?? persistentItems.first(where: { $0.diffId == itemView.diffId })
	}
	
	private func itemView(at location: NSPoint?, in view: NSView) -> DockItemView? {
		guard let scrubber = scrubber(at: location, in: view), let itemView = scrubber.subview(in: view, at: location, of: DockItemView.self) else {
			return nil
		}
		if let location = location {
			let loc = NSPoint(x: location.x + 6, y: 12)
			if itemView.convert(itemView.iconView.frame, to: view).contains(loc) {
				return itemView
			}
		}
		return nil
	}
	
	private func itemView(for item: DockItem) -> DockItemView? {
		guard let result = cachedPersistentItemViews.first(where: { $0.diffId == item.diffId }) else {
			return cachedDockItemViews.first(where: { $0.diffId == item.diffId })
		}
		return result
	}
}

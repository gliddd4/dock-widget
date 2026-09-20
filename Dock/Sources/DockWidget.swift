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

class DockWidget: NSObject, PKWidget, PKScreenEdgeMouseDelegate {
	
	deinit {
	}
	
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
	
	/// Traffic lights (close / minimize / zoom) shown to the left of the dock.
	/// Touch only: they are never part of `dockItems`, so the Option+1..9
	/// app-switch hotkeys cannot reach them.
	private var trafficLights:               NSStackView! = NSStackView(frame: .zero)
	private var trafficLightButtons:         [TrafficLightButton] = []
	private var trafficLightSizeConstraints: [NSLayoutConstraint] = []
	private var trafficLightHovered:         TrafficLightButton?

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

	/// Periodically re-checks whether Finder actually has open windows,
	/// so it can show as inactive on the widget (the real Dock always
	/// paints Finder as running, even with no windows).
	private var finderRefreshTimer: Timer?

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
		/// Added before the dock scrubber so the traffic lights sit to its left.
		self.configureTrafficLights()
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
		/// Reorder apps most-recently-used first (like the iOS app switcher)
		NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(handleAppActivated(_:)),
											  name: NSWorkspace.didActivateApplicationNotification, object: nil)
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
		/// While FL Studio is frontmost its own Option+number shortcuts must not be
		/// stolen, so the app-switch hotkeys become Option+Shift+1..9 there
		syncHotKeysForFrontmostApp()
		/// Option+W/S: warp the cursor into the foreground window and scroll with W/S
		MouseScrollController.shared.start()
		/// Keep the Finder item's running state in sync with its actual windows
		finderRefreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
			DispatchQueue.main.async {
				self?.refreshFinderRunningState()
			}
		}
	}

	/// FL Studio uses Option+number for its own shortcuts, so while it is the
	/// frontmost app the dock's app-switch hotkeys flip to Option+Shift+1..9 and
	/// the plain Option+number combos are released back to FL Studio.
	private func syncHotKeysForFrontmostApp() {
		let isFLStudio = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Constants.kFLStudioIdentifier
		OptionNumberHotKeys.shared.setAppSwitchRequiresShift(isFLStudio)
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
		case 14:
			MediaController.togglePlayPause()
		case 15:
			MediaController.previousTrack()
		case 16:
			MediaController.nextTrack()
		case 17:
			MediaController.adjustVolume(by: 0.04)
		case 18:
			MediaController.adjustVolume(by: -0.04)
		default:
			break
		}
	}

	/// Grow/shrink the dock item height by `delta` points and re-layout live.
	private func adjustItemHeight(by delta: CGFloat) {
		let newHeight = min(max(currentItemHeight + delta, 20), 48)
		currentItemHeight = newHeight
		/// The traffic lights track the icon size so they stay the same size
		updateTrafficLightSize()
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
		dockScrubber.scrubberLayout = makeDockLayout()
		dockScrubber.reloadData()
	}
	
	func viewDidAppear() {
		initialize()
		/// Make the scrubber fill the widget view's actual height so icons never clip
		DispatchQueue.main.async { [weak self] in
			guard let self = self else { return }
			self.dockScrubber.frame.size.height = self.stackView.bounds.height
			self.dockScrubber.reloadData()
		}
	}
	
	func viewDidDisappear() {
		MouseScrollController.shared.stop()
		finderRefreshTimer?.invalidate()
		finderRefreshTimer = nil
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

	/// Snapshot each cached item view's current frame (keyed by diffId) so
	/// item views can be slid from it to their post-relayout frames.
	private func snapshotItemFrames() -> [Int: NSRect] {
		var frames: [Int: NSRect] = [:]
		for view in cachedDockItemViews {
			frames[view.diffId] = view.frame
		}
		return frames
	}

	/// Reload the scrubber layout, sliding item views to their new positions
	/// (and the frontmost item's new width) instead of snapping instantly.
	private func relayoutScrubber(animated: Bool = true) {
		let oldFrames = animated ? snapshotItemFrames() : [:]
		dockScrubber.scrubberLayout = makeDockLayout()
		dockScrubber.reloadData()
		guard animated else {
			return
		}
		/// Wait a runloop tick so NSScrubber has applied the new frames,
		/// then animate each view from its old frame to its current one.
		DispatchQueue.main.async { [weak self] in
			self?.animateItemSlide(from: oldFrames)
		}
	}

	/// Animate every visible item view from its pre-relayout frame to its
	/// current one. Only the horizontal component is animated: an item slides
	/// sideways into its new slot and never moves vertically. The frontmost
	/// item also animates its width so the name area grows smoothly and pushes
	/// its neighbours aside.
	private func animateItemSlide(from oldFrames: [Int: NSRect]) {
		let duration: TimeInterval = 0.28
		for view in cachedDockItemViews {
			guard let oldFrame = oldFrames[view.diffId],
				  !oldFrame.isNull,
				  oldFrame != view.frame else {
				continue
			}
			guard let layer = view.layer ?? {
				view.wantsLayer = true
				return view.layer
			}() else {
				continue
			}
			let newFrame = view.frame
			/// Horizontal only — `position.x`, never `position`, so an item can
			/// never drift up or down on its way to its new slot.
			let position = CABasicAnimation(keyPath: "position.x")
			position.fromValue = NSNumber(value: Double(oldFrame.midX))
			position.toValue   = NSNumber(value: Double(newFrame.midX))
			position.duration  = duration
			position.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
			layer.add(position, forKey: "dockItemSlidePosition")
			/// Only the width ever changes (the frontmost item grows to reveal
			/// its name); the height is fixed, so nothing moves vertically.
			if oldFrame.width != newFrame.width {
				let bounds = CABasicAnimation(keyPath: "bounds")
				bounds.fromValue = NSValue(rect: NSRect(origin: .zero, size: oldFrame.size))
				bounds.toValue   = NSValue(rect: NSRect(origin: .zero, size: newFrame.size))
				bounds.duration  = duration
				bounds.timingFunction = position.timingFunction
				layer.add(bounds, forKey: "dockItemSlideBounds")
			}
		}
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

	/// Three squircles the size of a dock icon, in the classic window-control
	/// colours, sitting to the left of the dock. Touch only by design: they are
	/// not dock items, so Option+1..9 skips straight past them.
	private func configureTrafficLights() {
		guard trafficLightButtons.isEmpty else {
			return
		}
		trafficLights.orientation = .horizontal
		trafficLights.alignment   = .centerY
		trafficLights.spacing     = 6
		/// #ff6057 close, #febd30 minimize, #2ac840 zoom
		let specs: [(NSColor, TrafficLightAction)] = [
			(NSColor(srgbRed: 1.000, green: 0.376, blue: 0.341, alpha: 1), .close),
			(NSColor(srgbRed: 0.996, green: 0.741, blue: 0.188, alpha: 1), .minimize),
			(NSColor(srgbRed: 0.165, green: 0.784, blue: 0.251, alpha: 1), .zoom)
		]
		for (color, action) in specs {
			let button = TrafficLightButton(color: color, action: action)
			trafficLightButtons.append(button)
			trafficLights.addArrangedSubview(button)
		}
		stackView.addArrangedSubview(trafficLights)
		updateTrafficLightSize()
	}

	/// Keep the traffic lights exactly the size of a dock icon, following the
	/// Option+[ / ] size calibration.
	private func updateTrafficLightSize() {
		guard trafficLightButtons.isEmpty == false else {
			return
		}
		let side = currentItemHeight
		if trafficLightSizeConstraints.isEmpty {
			trafficLightSizeConstraints = trafficLightButtons.flatMap {
				[$0.width(side), $0.height(side)]
			}
		}else {
			trafficLightSizeConstraints.forEach { $0.constant = side }
		}
		trafficLightButtons.forEach {
			$0.cornerRadius = side * TrafficLightButton.cornerRadiusRatio
		}
	}

	/// The traffic-light button under `location`, if any.
	private func trafficLightButton(at location: NSPoint, in view: NSView) -> TrafficLightButton? {
		return trafficLightButtons.first {
			$0.convert($0.bounds, to: view).contains(location)
		}
	}

	private func updateTrafficLightHover(_ location: NSPoint?, in view: NSView) {
		let hovered = location.flatMap { trafficLightButton(at: $0, in: view) }
		guard hovered !== trafficLightHovered else {
			return
		}
		trafficLightHovered?.set(isMouseOver: false)
		hovered?.set(isMouseOver: true)
		trafficLightHovered = hovered
	}

	/// Drive the frontmost app's window the way its own traffic lights would, by
	/// pressing that window's Accessibility button.
	private func perform(_ action: TrafficLightAction) {
		guard let app = NSWorkspace.shared.frontmostApplication else {
			return
		}
		let appElement = AXUIElementCreateApplication(app.processIdentifier)
		guard let window = frontWindow(appElement) else {
			NSLog("[DockWidget]: Traffic light: no window for \(app.bundleIdentifier ?? "frontmost app")")
			return
		}
		let attribute: CFString
		switch action {
		case .close:    attribute = kAXCloseButtonAttribute as CFString
		case .minimize: attribute = kAXMinimizeButtonAttribute as CFString
		case .zoom:     attribute = kAXZoomButtonAttribute as CFString
		}
		guard let value = copyAttribute(window, attribute),
			  CFGetTypeID(value) == AXUIElementGetTypeID() else {
			NSLog("[DockWidget]: Traffic light: no \(attribute as String) on the frontmost window")
			return
		}
		AXUIElementPerformAction(value as! AXUIElement, kAXPressAction as CFString)
	}

	/// The frontmost app's focused window, falling back to its first window.
	private func frontWindow(_ appElement: AXUIElement) -> AXUIElement? {
		if let value = copyAttribute(appElement, kAXFocusedWindowAttribute as CFString),
		   CFGetTypeID(value) == AXUIElementGetTypeID() {
			return value as! AXUIElement
		}
		if let windows = copyAttribute(appElement, kAXWindowsAttribute as CFString) as? [AXUIElement] {
			return windows.first
		}
		return nil
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
	
	// MARK: ScreenEdgeMouseDelegate (Select, Scroll & Drag)
	func screenEdgeController(_ controller: PKScreenEdgeController, mouseEnteredAtLocation location: NSPoint, in view: NSView) {
		updateCursorLocation(location, in: view)
	}
	
	func screenEdgeController(_ controller: PKScreenEdgeController, mouseExitedAtLocation location: NSPoint, in view: NSView) {
		itemViewWithMouseOver?.set(isMouseOver: false)
		updateTrafficLightHover(nil, in: view)
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
		/// Traffic lights are hit-tested first: they sit outside the dock, so a
		/// tap on one must never fall through to an app launch.
		if let button = trafficLightButton(at: location, in: view) {
			perform(button.action)
			return
		}
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
				NSLog("[DockWidget]: Move to trash error: \(error.localizedDescription)")
				NSSound.beep()
				return false
			}
		}
		return false
	}
	
	private func updateCursorLocation(_ location: NSPoint?, in view: NSView) {
		updateTrafficLightHover(location, in: view)
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
						itemView.set(isRunning:   effectiveIsRunning(item))
						itemView.set(isFrontmost: self.frontmostDiffId == item.diffId)
						itemView.set(isLaunching: item.isLaunching)
						self.dockScrubber.reloadItems(at: IndexSet(integer: currentIndex))
					}
				}
			}else {
				if self.dockItems.contains(item) == false {
					/// Always append, then let applyDockOrder() put it in place.
					/// The old code spliced the item in at the repository's
					/// index, which replaced whatever already sat in that slot
					/// and silently dropped an app out of the dock.
					let validIndex = self.dockItems.count
					self.dockItems.append(item)
					self.dockScrubber.insertItems(at: IndexSet(integer: validIndex))
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
			self.applyDockOrder()
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
			/// our Dock ordering. Using that stale index highlights the wrong
			/// item and reveals the wrong name.
			guard let currentIndex = self.dockItems.firstIndex(where: { $0.diffId == item.diffId }) else {
				return
			}
			/// Only an activation moves the highlight. Handling the matching
			/// deactivation as well collapsed the old name and then re-revealed
			/// the new one, so every app switch became a two-step shuffle.
			guard activated else {
				return
			}
			self.applyFrontmost(currentIndex)
			/// Deliberately no scroll-to-centre. The dock is only about ten items
			/// wide and always fits the bar, so re-centring the active app on every
			/// switch slid the other icons around for no reason.
			self.relayoutScrubber()
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
		view.set(isRunning:   effectiveIsRunning(item))
		view.set(isFrontmost: frontmostDiffId == item.diffId)
		return view
	}

	/// Put the items back into the Dock's own order. The order is a property of
	/// the Dock, never of what happens to be running or was last activated, so
	/// this is the only thing that ever reorders the items. Apps that are
	/// running but not pinned in the Dock sort to the end, which is where the
	/// real Dock shows them.
	private func applyDockOrder() {
		let order = dockRepository?.dockOrder ?? []
		guard order.isEmpty == false else {
			return
		}
		/// Rank by position in the Dock; unpinned apps rank last and ties keep
		/// their existing relative order.
		func rank(_ item: DockItem) -> Int {
			guard let identifier = item.bundleIdentifier,
				  let index = order.firstIndex(of: identifier) else {
				return Int.max
			}
			return index
		}
		let reordered = dockItems.enumerated().sorted { lhs, rhs in
			let lhsRank = rank(lhs.element)
			let rhsRank = rank(rhs.element)
			return lhsRank == rhsRank ? lhs.offset < rhs.offset : lhsRank < rhsRank
		}.map { $0.element }
		/// Keep the highlight on the same app, and drop it when that app is gone.
		/// A stale index would otherwise highlight the wrong icon, or index out
		/// of bounds after a removal.
		if let index = frontmostIndex {
			if index >= 0, index < dockItems.count,
			   let remapped = reordered.firstIndex(where: { $0.diffId == dockItems[index].diffId }) {
				frontmostIndex = remapped
			}else {
				applyFrontmost(nil)
			}
		}
		guard reordered != dockItems else {
			return
		}
		dockItems = reordered
		relayoutScrubber()
	}

	/// Activation no longer moves anything: the dock order is fixed, so the
	/// only thing left to do here is keep the app-switch hotkeys in sync.
	@objc private func handleAppActivated(_ notification: Notification) {
		DispatchQueue.main.async { [weak self] in
			self?.syncHotKeysForFrontmostApp()
		}
	}

	/// Running state as it should be displayed on the widget. Finder is
	/// always technically running, so judge it by whether it actually has
	/// open (non-minimized) windows, like the Launchpad view does.
	private func effectiveIsRunning(_ item: DockItem) -> Bool {
		guard item.bundleIdentifier == Constants.kFinderIdentifier,
			  let app = NSRunningApplication.runningApplications(withBundleIdentifier: Constants.kFinderIdentifier).first else {
			return item.isRunning
		}
		return hasVisibleWindow(app)
	}

	/// Sync the Finder item with its actual window state (no workspace
	/// notification fires when the last Finder window closes, so poll)
	@objc private func refreshFinderRunningState() {
		guard let item = dockItems.first(where: { $0.bundleIdentifier == Constants.kFinderIdentifier }) else {
			return
		}
		let running = effectiveIsRunning(item)
		guard let itemView = itemView(for: item), itemView.isRunning != running else {
			return
		}
		itemView.set(isRunning: running)
		if let index = dockItems.firstIndex(where: { $0.diffId == item.diffId }) {
			dockScrubber.reloadItems(at: IndexSet(integer: index))
		}
		applyDockOrder()
	}

	/// The highlighted item's diffId, or nil when the tracked index is stale.
	/// Reading `dockItems[frontmostIndex]` directly could trap after a removal.
	private var frontmostDiffId: Int? {
		guard let index = frontmostIndex, index >= 0, index < dockItems.count else {
			return nil
		}
		return dockItems[index].diffId
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
		let indexIsFrontmost = frontmostDiffId == item.diffId
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

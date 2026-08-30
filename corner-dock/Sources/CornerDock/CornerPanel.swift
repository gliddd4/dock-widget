//
//  CornerPanel.swift
//  CornerDock
//
//  A single bottom-corner hover panel. Hidden state: only a thin strip
//  peeks above the bottom edge at low opacity. On hover it slides up
//  from the corner and fades in. Click opens the target in Finder.
//

import AppKit

final class CornerPanel: NSPanel {

	enum Kind {
		case trash
		case downloads

		var title: String {
			switch self {
			case .trash: return "Trash"
			case .downloads: return "Downloads"
			}
		}

		var path: String {
			switch self {
			case .trash: return NSHomeDirectory() + "/.Trash"
			case .downloads: return NSHomeDirectory() + "/Downloads"
			}
		}

		var onRightSide: Bool {
			switch self {
			case .trash: return true
			case .downloads: return false
			}
		}

		var icon: NSImage? {
			switch self {
			case .trash:
				let empty = (try? FileManager.default.contentsOfDirectory(atPath: path).isEmpty) ?? true
				return NSImage(contentsOfFile: "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/\(empty ? "TrashIcon" : "FullTrashIcon").icns")
			case .downloads:
				return NSWorkspace.shared.icon(forFile: path)
			}
		}
	}

	static let panelSize   = NSSize(width: 116, height: 78)
	static let peekHeight: CGFloat = 3

	let kind: Kind
	private let iconView = NSImageView(frame: .zero)
	private let titleLabel = NSTextField(labelWithString: "")
	private var iconRefreshTimer: Timer?

	init(kind: Kind) {
		self.kind = kind
		let styleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]
		super.init(contentRect: NSRect(origin: .zero, size: Self.panelSize),
				   styleMask: styleMask,
				   backing: .buffered,
				   defer: false)
		isOpaque = false
		backgroundColor = .clear
		level = .statusBar
		isFloatingPanel = true
		becomesKeyOnlyIfNeeded = true
		worksWhenModal = true
		hidesOnDeactivate = false
		acceptsMouseMovedEvents = true
		collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
		ignoresMouseEvents = false
		hasShadow = false
		let container = makeContentView()
		container.frame = NSRect(origin: .zero, size: Self.panelSize)
		container.autoresizingMask = [.width, .height]
		container.wantsLayer = true
		container.layer?.cornerRadius = 14
		container.layer?.backgroundColor = NSColor(white: 0.08, alpha: 0.92).cgColor
		container.layer?.masksToBounds = true
		super.contentView = container

		let tracking = NSTrackingArea(rect: NSRect(origin: .zero, size: Self.panelSize),
									  options: [.mouseEnteredAndExited, .activeAlways],
									  owner: self,
									  userInfo: nil)
		container.addTrackingArea(tracking)

		let click = NSClickGestureRecognizer(target: self, action: #selector(openTarget))
		container.addGestureRecognizer(click)

		refreshIcon()
		alphaValue = 0
	}

	private func makeContentView() -> NSView {
		let container = NSView()
		iconView.imageScaling = .scaleProportionallyDown
		iconView.wantsLayer = true
		iconView.frame = NSRect(x: (Self.panelSize.width - 44) / 2, y: 24, width: 44, height: 44)
		container.addSubview(iconView)

		titleLabel.stringValue = kind.title
		titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
		titleLabel.textColor = .white
		titleLabel.alignment = .center
		titleLabel.frame = NSRect(x: 4, y: 7, width: Self.panelSize.width - 8, height: 14)
		container.addSubview(titleLabel)
		return container
	}

	// MARK: Positioning

	func position(on screen: NSScreen?) {
		guard let screen = screen else { return }
		let size = Self.panelSize
		let x = kind.onRightSide
			? screen.frame.maxX - size.width
			: screen.frame.minX
		let hiddenOrigin = NSPoint(x: x, y: screen.frame.minY - size.height + Self.peekHeight)
		setFrameOrigin(hiddenOrigin)
	}

	private var screen: NSScreen? { NSScreen.main }

	private var hiddenOrigin: NSPoint {
		guard let screen = screen else { return .zero }
		let size = Self.panelSize
		let x = kind.onRightSide
			? screen.frame.maxX - size.width
			: screen.frame.minX
		return NSPoint(x: x, y: screen.frame.minY - size.height + Self.peekHeight)
	}

	private var shownOrigin: NSPoint {
		guard let screen = screen else { return .zero }
		let size = Self.panelSize
		let x = kind.onRightSide
			? screen.frame.maxX - size.width
			: screen.frame.minX
		return NSPoint(x: x, y: screen.frame.minY)
	}

	// MARK: Show / hide

	override func mouseEntered(with event: NSEvent) {
		show()
	}

	override func mouseExited(with event: NSEvent) {
		hide()
	}

	private func show() {
		refreshIcon()
		iconRefreshTimer?.invalidate()
		iconRefreshTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
			self?.refreshIcon()
		}
		setFrameOrigin(shownOrigin)
		NSAnimationContext.runAnimationGroup { context in
			context.duration = 0.22
			context.timingFunction = CAMediaTimingFunction(name: .easeOut)
			self.animator().alphaValue = 1
		}
	}

	private func hide() {
		iconRefreshTimer?.invalidate()
		iconRefreshTimer = nil
		NSAnimationContext.runAnimationGroup({ context in
			context.duration = 0.22
			context.timingFunction = CAMediaTimingFunction(name: .easeIn)
			self.animator().alphaValue = 0
		}, completionHandler: {
			self.setFrameOrigin(self.hiddenOrigin)
		})
	}

	// MARK: Actions

	@objc private func openTarget() {
		NSWorkspace.shared.open(URL(fileURLWithPath: kind.path))
	}

	private func refreshIcon() {
		iconView.image = kind.icon
	}

}

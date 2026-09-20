//
//  DockItemView.swift
//  Pock
//
//  Created by Pierluigi Galdi on 06/04/2019.
//  Copyright © 2019 Pierluigi Galdi. All rights reserved.
//

import Foundation
import CoreImage
import TinyConstraints

class DockItemView: NSScrubberItemView {

    /// Core
    private var isAnimating: Bool = false
	private var isMouseOver: Bool = false
	public  var diffId: Int!

    /// UI
    public private(set) var contentView:   NSView!
    public private(set) var iconView:      NSImageView!
    public private(set) var badgeView:     NSView!
	private private(set) var nameLabel:    NSTextField!
	private var nameLabelWidthConstraint: NSLayoutConstraint?

	/// Load icon view (fills the whole item height, square, adaptive)
    private func loadIconView() {
        self.iconView = NSImageView(frame: .zero)
        self.iconView.imageScaling = .scaleProportionallyUpOrDown
        self.iconView.wantsLayer = true
        self.contentView.addSubview(self.iconView)
		/// Boost color saturation of app icons
		if let filter = CIFilter(name: "CIColorControls") {
			filter.setValue(1.5, forKey: kCIInputSaturationKey)
			filter.setValue(1.05, forKey: kCIInputContrastKey)
			self.iconView.layer?.filters = [filter]
		}
        self.iconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            self.iconView.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor, constant: 0),
            self.iconView.centerYAnchor.constraint(equalTo: self.contentView.centerYAnchor),
            self.iconView.heightAnchor.constraint(equalTo: self.contentView.heightAnchor),
            self.iconView.widthAnchor.constraint(equalTo: self.iconView.heightAnchor)
        ])
    }

    /// Load name label (only visible for the frontmost item)
	private func loadNameLabel() {
		self.nameLabel = NSTextField(labelWithString: "")
		self.nameLabel.font = NSFont.systemFont(ofSize: Constants.nameFontSize, weight: .medium)
		self.nameLabel.textColor = .white
		self.nameLabel.lineBreakMode = .byTruncatingTail
		self.nameLabel.usesSingleLineMode = true
		self.nameLabel.cell?.truncatesLastVisibleLine = true
		self.nameLabel.alignment = .left
		self.nameLabel.wantsLayer = true
		self.nameLabel.layer?.opacity = 0
		self.contentView.addSubview(self.nameLabel)
		self.nameLabel.centerYToSuperview()
		self.nameLabel.leadingToTrailing(of: self.iconView, offset: Constants.nameHorizontalPadding)
		nameLabelWidthConstraint = self.nameLabel.width(0)
		self.nameLabel.width(min: 0, max: Constants.nameMaxWidth)
	}

    /// Load badge view
    private func loadBadgeView() {
        self.badgeView = NSView(frame: NSRect(origin: .zero, size: Constants.dockItemBadgeSize))
        self.badgeView.wantsLayer = true
        self.badgeView.layer?.cornerRadius = Constants.dockItemBadgeSize.width / 2
        self.badgeView.layer?.backgroundColor = NSColor.red.cgColor
        self.contentView.addSubview(self.badgeView, positioned: .above, relativeTo: self.iconView)
		self.badgeView.size(Constants.dockItemBadgeSize)
		self.badgeView.top(to: iconView, offset: -1)
		self.badgeView.centerXToSuperview(offset: 10)
    }

    /// Init
    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(origin: .zero, size: Constants.dockItemSize))
        self.contentView = NSView(frame: .zero)
        self.addSubview(self.contentView)
		self.contentView.edgesToSuperview()
    }

    required init?(coder decoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func clear() {
        self.set(icon:        nil)
        self.set(name:        nil)
        self.set(hasBadge:    false)
        self.set(isRunning:   false)
        self.set(isFrontmost: false)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        layer?.contentsScale                = window?.backingScaleFactor ?? 1
        iconView?.layer?.contentsScale      = window?.backingScaleFactor ?? 1
        badgeView?.layer?.contentsScale     = window?.backingScaleFactor ?? 1
        nameLabel?.layer?.contentsScale     = window?.backingScaleFactor ?? 1
    }

    /// Launch state is tracked but deliberately does not animate: dock items
    /// must never move vertically, so a launching app stays exactly where it is.
    public func set(isLaunching: Bool) {
        self.isAnimating = isLaunching
    }
    public var isLaunching: Bool { return self.isAnimating }

    public func set(icon: NSImage?) {
        if iconView == nil { loadIconView() }
        iconView.image = icon
    }

	public func set(name: String?) {
		if nameLabel == nil { loadNameLabel() }
		let text = name ?? ""
		nameLabel.attributedStringValue = NSAttributedString(string: text, attributes: [
			.foregroundColor: NSColor.white,
			.font: NSFont.systemFont(ofSize: Constants.nameFontSize, weight: .medium)
		])
		let field = NSTextField(labelWithString: text)
		field.font = NSFont.systemFont(ofSize: Constants.nameFontSize, weight: .medium)
		let size = field.sizeThatFits(NSSize(width: Constants.nameMaxWidth, height: Constants.dockItemSize.height))
		nameWidth = ceil(size.width)
	}

	/// Closed apps are dimmed to 50% opacity (replaces the running-indicator dot)
    public func set(isRunning: Bool) {
        if iconView == nil { loadIconView() }
		iconView.layer?.opacity = isRunning ? 1 : 0.5
    }
    public var isRunning: Bool { return iconView.layer?.opacity == 1 }

    public func set(hasBadge: Bool) {
        if badgeView == nil { loadBadgeView() }
        badgeView.layer?.opacity = hasBadge ? 1 : 0
    }
    public var hasBadge: Bool { return badgeView.layer?.opacity == 1 }

	/// Frontmost: animated name reveal to the right of the icon (no square box)
	public func set(isFrontmost: Bool) {
		if nameLabel == nil { loadNameLabel() }
		isFrontmostState = isFrontmost
		revealName(isFrontmost)
	}

	/// Measured name width (0 when no name)
	fileprivate var nameWidth: CGFloat = 0

	private func revealName(_ show: Bool) {
		let label = nameLabel.layer!
		label.removeAnimation(forKey: "nameReveal")
		let transition = CATransition()
		transition.type = .push
		transition.subtype = show ? .fromLeft : .fromRight
		transition.duration = 0.28
		transition.timingFunction = CAMediaTimingFunction(name: .easeOut)
		label.add(transition, forKey: "nameReveal")
		label.opacity = show ? 1 : 0
		/// Grow the width constraint so the text is actually visible next to the icon
		nameLabelWidthConstraint?.constant = show ? nameWidth : 0
	}

	public private(set) var isFrontmostState: Bool = false
	public var isFrontmost: Bool { return isFrontmostState }

	public func set(isMouseOver: Bool) {
		guard isMouseOver else {
			iconView.shadow = nil
			return
		}
		let shadow = NSShadow()
		shadow.shadowBlurRadius = 5
		shadow.shadowOffset		= NSSize(width: 0, height: -2.35)
		shadow.shadowColor		= NSColor.white
		iconView.shadow = shadow
	}

}

// The launch bounce was removed deliberately. It animated `position.y` on the
// icon and badge, and because `animationDidStop` restarted it whenever
// `isAnimating` had been cleared, a stopped item could keep bouncing on its
// own. Dock items must only ever slide horizontally, so `isLaunching` is now
// tracked without any motion.

/// What a traffic-light button does to the frontmost window.
enum TrafficLightAction {
	case close
	case minimize
	case zoom
}

/// A squircle button sitting to the left of the dock, styled like one of the
/// macOS window controls. These are touch-only: they are deliberately kept out
/// of `dockItems`, so the Option+1..9 app-switch hotkeys can never select them.
///
/// Sizing note: the button is drawn edge to edge, so its frame *is* its visible
/// size. A dock icon is not — the artwork only fills 824/1024 of the icon's
/// box. The button therefore has to be sized to the icon's visible artwork
/// (see `Constants.dockIconArtworkRatio`), not to the icon's box, or the flat
/// colour makes it look a quarter larger than the icons beside it.
final class TrafficLightButton: NSView {

	/// macOS app icons are continuous-corner rounded squares, and the ratio is
	/// measured against the artwork rather than the box, so applying it to the
	/// button's visible side reproduces the icon's curve exactly. A full circle
	/// would be `0.5`; this is deliberately the icon shape instead.
	static let cornerRadiusRatio: CGFloat = 0.2237

	/// The visible side the button starts at, before the container lays it out.
	static var defaultSide: CGFloat {
		return Constants.dockItemSize.height * Constants.dockIconArtworkRatio
	}

	let action: TrafficLightAction

	/// Called when the button is tapped. The widget owns the window-driving code,
	/// so it supplies this rather than the button doing the work itself.
	var onTap: (() -> Void)?

	init(color: NSColor, action: TrafficLightAction) {
		self.action = action
		let side = TrafficLightButton.defaultSide
		super.init(frame: NSRect(x: 0, y: 0, width: side, height: side))
		self.wantsLayer = true
		self.layer?.backgroundColor = color.cgColor
		self.cornerRadius = side * TrafficLightButton.cornerRadiusRatio
		/// A Touch Bar touch is a **direct** touch, and a view only receives
		/// direct touches if a gesture recogniser opts in through
		/// `allowedTouchTypes` — the default is indirect only, which is why a
		/// plain `NSView` (and any hit-testing of it) is completely inert on the
		/// Touch Bar. This is exactly how PockKit's own Touch Bar button,
		/// `PKButton`, makes itself tappable, and it is why the dock itself works:
		/// `NSScrubber` handles direct touches for its items internally.
		let click = NSClickGestureRecognizer(target: self, action: #selector(handleTap))
		click.allowedTouchTypes = .direct
		addGestureRecognizer(click)
	}

	@objc private func handleTap() {
		onTap?()
	}

	required init?(coder decoder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	/// Continuous corner curve is what makes it a squircle rather than a plain
	/// rounded rect, which is what the dock icons use. The radius is the icon
	/// ratio of the side, not half of it — these are squircles, not circles.
	var cornerRadius: CGFloat = 0 {
		didSet {
			layer?.cornerCurve  = .continuous
			layer?.cornerRadius = cornerRadius
		}
	}

	/// A light ring on hover, so the Touch Bar gives some feedback that the
	/// button is touchable.
	func set(isMouseOver: Bool) {
		layer?.borderWidth = isMouseOver ? 2 : 0
		layer?.borderColor = NSColor.white.withAlphaComponent(0.85).cgColor
	}

}

/// Holds the traffic lights to the left of the dock.
///
/// This deliberately reports **no intrinsic height** and positions its buttons
/// by hand, the same way `NSScrubber` handles the dock icons. A required height
/// constraint on the buttons would become the widget view's minimum height, and
/// since the buttons are a dock icon tall (taller than the Touch Bar) the view
/// would grow past the bar and clip the top of everything. Letting the buttons
/// overflow a container that is exactly the bar's height keeps the geometry
/// identical to the dock icons: a dock icon tall, clipped top and bottom by the
/// bar in exactly the same way.
final class TrafficLightsView: NSView {

	/// Gap between buttons, edge to edge. The caller sets this to the gap the eye
	/// sees between two dock icons; it is not the dock's raw `itemSpacing`, which
	/// is much smaller because each item also reserves icon-box padding.
	var spacing: CGFloat = 0 {
		didSet {
			guard spacing != oldValue else { return }
			invalidateIntrinsicContentSize()
			needsLayout = true
		}
	}

	/// Side of one button. This is the button's **visible** size, which the
	/// caller sets to the dock icon's visible artwork size — see
	/// `Constants.dockIconArtworkRatio` and the note on `TrafficLightButton`.
	var side: CGFloat = TrafficLightButton.defaultSide {
		didSet {
			buttons.forEach { $0.cornerRadius = side * TrafficLightButton.cornerRadiusRatio }
			invalidateIntrinsicContentSize()
			needsLayout = true
		}
	}

	/// Absolute y — in this view's own coordinate space — that the buttons'
	/// centres must sit on. `nil` falls back to the view's own centre.
	///
	/// Stored as a position rather than a delta so it stays correct if the
	/// container is ever resized; the caller measures it from a real dock item
	/// view, which is the only reliable way to land on the icons' centre.
	var buttonCenterY: CGFloat? {
		didSet {
			guard buttonCenterY != oldValue else { return }
			needsLayout = true
		}
	}

	private(set) var buttons: [TrafficLightButton] = []

	func add(_ button: TrafficLightButton) {
		buttons.append(button)
		addSubview(button)
		invalidateIntrinsicContentSize()
		needsLayout = true
	}

	/// Width is intrinsic so the stack can allocate space; height is not, so the
	/// stack never sizes itself from these buttons.
	override var intrinsicContentSize: NSSize {
		let count = CGFloat(buttons.count)
		guard count > 0 else {
			return NSSize(width: 0, height: NSView.noIntrinsicMetric)
		}
		return NSSize(width: count * side + (count - 1) * spacing,
					  height: NSView.noIntrinsicMetric)
	}

	override func layout() {
		super.layout()
		guard buttons.isEmpty == false else {
			return
		}
		var x = (bounds.width - intrinsicContentSize.width) / 2
		/// Centre on the dock icons when we know where they are, otherwise on
		/// the bar. Buttons are centred on `buttonCenterY`, not placed at it.
		let y = (buttonCenterY ?? bounds.height / 2) - side / 2
		for button in buttons {
			button.frame = NSRect(x: x, y: y, width: side, height: side)
			x += side + spacing
		}
	}

}

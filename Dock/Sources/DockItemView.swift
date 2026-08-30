//
//  DockItemView.swift
//  Pock
//
//  Created by Pierluigi Galdi on 06/04/2019.
//  Copyright © 2019 Pierluigi Galdi. All rights reserved.
//

import Foundation
import TinyConstraints

class DockItemView: NSScrubberItemView {

    /// Core
    private static let kBounceAnimationKey: String = "kBounceAnimationKey"
    private var isAnimating: Bool = false
	private var isMouseOver: Bool = false
	public  var diffId: Int!

    /// UI
    public private(set) var contentView:   NSView!
    public private(set) var frontmostView: NSView!
    public private(set) var iconView:      NSImageView!
    public private(set) var badgeView:     NSView!
	private private(set) var nameLabel:    NSTextField!

	/// Load frontmost (square box around the item)
    private func loadFrontmost() {
        self.frontmostView = NSView(frame: .zero)
        self.frontmostView.wantsLayer = true
        self.frontmostView.layer?.masksToBounds = true
        self.frontmostView.layer?.cornerRadius = Constants.dockItemCornerRadius
        self.contentView.addSubview(self.frontmostView, positioned: .below, relativeTo: self.iconView)
		self.frontmostView.edgesToSuperview()
    }

    /// Load icon view
    private func loadIconView() {
        self.iconView = NSImageView(frame: .zero)
        self.iconView.imageScaling = .scaleProportionallyDown
        self.iconView.wantsLayer = true
        self.contentView.addSubview(self.iconView)
		self.iconView.size(Constants.dockItemIconSize)
		self.iconView.centerYToSuperview()
		self.iconView.leftToSuperview(offset: 4)
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
		self.nameLabel.width(0)
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
        frontmostView?.layer?.contentsScale = window?.backingScaleFactor ?? 1
        nameLabel?.layer?.contentsScale     = window?.backingScaleFactor ?? 1
    }

    public func set(isLaunching: Bool) {
        if isLaunching { startBounceAnimation() } else { stopBounceAnimation() }
    }
    public var isLaunching: Bool { return self.isAnimating }

    public func set(icon: NSImage?) {
        if iconView == nil { loadIconView() }
        iconView.image = icon
    }

	public func set(name: String?) {
		if nameLabel == nil { loadNameLabel() }
		nameLabel.stringValue = name ?? ""
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

	/// Frontmost: square box + animated name reveal
	public func set(isFrontmost: Bool) {
		if frontmostView == nil { loadFrontmost() }
		if nameLabel == nil { loadNameLabel() }
		let box = frontmostView.layer!
		box.removeAnimation(forKey: "boxTransition")
		let transition = CATransition()
		transition.type = .fade
		transition.duration = 0.2
		box.add(transition, forKey: "boxTransition")
		box.backgroundColor = (isFrontmost ? NSColor.darkGray : NSColor.clear).cgColor
		revealName(isFrontmost)
	}

	private func revealName(_ show: Bool) {
		let label = nameLabel.layer!
		label.removeAnimation(forKey: "nameReveal")
		let transition = CATransition()
		transition.type = .push
		transition.subtype = show ? .fromLeft : .fromRight
		transition.duration = 0.22
		transition.timingFunction = CAMediaTimingFunction(name: .easeOut)
		label.add(transition, forKey: "nameReveal")
		label.opacity = show ? 1 : 0
	}

	public var isFrontmost: Bool { return frontmostView.layer?.backgroundColor == NSColor.darkGray.cgColor }

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

extension DockItemView: CAAnimationDelegate {
    func startBounceAnimation() {
        if !isAnimating {
            self.loadBounceAnimation()
        }
    }
    private func loadBounceAnimation() {
        isAnimating           = true
        let bounce            = CABasicAnimation(keyPath: "position.y")
        bounce.byValue        = NSNumber(floatLiteral: 10)
        bounce.duration       = 0.325
        bounce.autoreverses   = true
		bounce.isRemovedOnCompletion = true
		bounce.delegate = self
        bounce.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.easeOut)
        let frame = self.iconView.layer?.frame
        self.iconView.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        self.iconView.layer?.frame = frame ?? .zero
        self.iconView.layer?.add(bounce, forKey: DockItemView.kBounceAnimationKey)
        self.badgeView?.layer?.add(bounce, forKey: DockItemView.kBounceAnimationKey)
    }
    func stopBounceAnimation() {
        self.isAnimating = false
    }
	func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
		startBounceAnimation()
	}
}

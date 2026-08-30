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
    private static let kBounceAnimationKey: String = "kBounceAnimationKey"
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
		transition.duration = 0.22
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

//
//  DockScrubberLayout.swift
//  Dock
//
//  Flow layout that gives the frontmost item extra width to fit its revealed name.
//

import Foundation
import AppKit

class DockScrubberLayout: NSScrubberFlowLayout {

	/// Index of the frontmost item (gets extra width for its name)
	var frontmostIndex: Int? = nil

	/// Returns the measured name width for an item (0 if no name to show)
	var nameWidthProvider: ((Int) -> CGFloat)? = nil

	private func width(at index: Int) -> CGFloat {
		if index == frontmostIndex, let nameWidth = nameWidthProvider?(index), nameWidth > 0 {
			return Constants.dockItemSize.width + Constants.nameHorizontalPadding + min(nameWidth, Constants.nameMaxWidth)
		}
		return Constants.dockItemSize.width
	}

	override func layoutAttributesForItem(at index: Int) -> NSScrubberLayoutAttributes {
		let attributes = NSScrubberLayoutAttributes(forItemAt: index)
		var x: CGFloat = 0
		if index > 0 {
			for i in 0..<index {
				x += width(at: i) + itemSpacing
			}
		}
		attributes.frame = NSRect(origin: NSPoint(x: x, y: 0),
								  size: NSSize(width: width(at: index), height: itemSize.height))
		return attributes
	}

	override var scrubberContentSize: NSSize {
		let count = scrubber?.numberOfItems ?? 0
		guard count > 0 else {
			return .zero
		}
		var total: CGFloat = 0
		for i in 0..<count {
			total += width(at: i)
		}
		total += itemSpacing * CGFloat(count - 1)
		return NSSize(width: total, height: itemSize.height)
	}

}

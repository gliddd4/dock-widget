//
//  DockScrubberLayout.swift
//  Dock
//
//  Custom scrubber layout that gives the frontmost item extra width to
//  fit its revealed name, pushing the other items to the side.
//
//  We subclass NSScrubberLayout directly (not NSScrubberFlowLayout):
//  the flow layout caches item frames from its own itemSize/itemSpacing
//  and never consults a subclass override of layoutAttributesForItem,
//  so per-item widths would silently be ignored.
//

import Foundation
import AppKit

class DockScrubberLayout: NSScrubberLayout {

	/// Index of the frontmost item (gets extra width for its name)
	var frontmostIndex: Int? = nil

	/// Returns the measured name width for an item (0 if no name to show)
	var nameWidthProvider: ((Int) -> CGFloat)? = nil

	/// Item metrics (same names as NSScrubberFlowLayout for compatibility)
	var itemSize:    NSSize   = Constants.dockItemSize
	var itemSpacing: CGFloat  = 2

	/// Frames computed in prepareLayout()
	private var cachedFrames:       [NSRect] = []
	private var cachedContentSize:  NSSize   = .zero

	private func width(at index: Int) -> CGFloat {
		if index == frontmostIndex, let nameWidth = nameWidthProvider?(index), nameWidth > 0 {
			return itemSize.width + Constants.nameHorizontalPadding + min(nameWidth, Constants.nameMaxWidth)
		}
		return itemSize.width
	}

	override func prepare() {
		super.prepare()
		let count = scrubber?.numberOfItems ?? 0
		/// Center items vertically within the scrubber, nudged down 5pt so the
		/// icons sit fully inside the visible bar instead of clipping at the top
		let scrubberHeight = scrubber?.bounds.height ?? itemSize.height
		let y = max(0, (scrubberHeight - itemSize.height) / 2) + Constants.dockItemVerticalOffset
		var frames: [NSRect] = []
		var x: CGFloat = 0
		for i in 0..<count {
			frames.append(NSRect(x: x, y: y, width: width(at: i), height: itemSize.height))
			x += width(at: i) + itemSpacing
		}
		cachedFrames = frames
		let totalWidth = count > 0 ? x - itemSpacing : 0
		cachedContentSize = NSSize(width: totalWidth, height: scrubberHeight)
	}

	override var scrubberContentSize: NSSize {
		return cachedContentSize
	}

	override func layoutAttributesForItem(at index: Int) -> NSScrubberLayoutAttributes? {
		guard index >= 0, index < cachedFrames.count else {
			return nil
		}
		let attributes = NSScrubberLayoutAttributes(forItemAt: index)
		attributes.frame = cachedFrames[index]
		return attributes
	}

	override func layoutAttributesForItems(in rect: NSRect) -> Set<NSScrubberLayoutAttributes> {
		return Set(cachedFrames.indices.compactMap { layoutAttributesForItem(at: $0) })
	}

	override func shouldInvalidateLayoutForChange(fromVisibleRect: NSRect, toVisibleRect: NSRect) -> Bool {
		return true
	}

}

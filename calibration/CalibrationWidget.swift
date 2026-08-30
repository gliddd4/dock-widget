//
//  CalibrationWidget.swift
//  Calibration
//
//  Draws a 1px white/red grid across the widget so you can measure the
//  real visible height of the Touch Bar. The widget view is fixed at
//  30pt by Pock, but the grid can be drawn taller ("virtual height")
//  with Option+Left/Right; rows above the visible edge are clipped,
//  showing exactly where the bar ends. Option+Up/Down moves the grid
//  vertically so you can align it with either edge.
//

import AppKit
import PockKit
import Carbon

final class CalibrationGridView: NSView {

    /// Total grid height to draw (can exceed the visible 30pt)
    var virtualHeight: CGFloat = 30
    /// Shifts the grid vertically (negative = down)
    var offset: CGFloat = 0

    override var isFlipped: Bool { return false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let w = bounds.width
        let top = bounds.height

        // Background
        NSColor.black.setFill()
        bounds.fill()

        // 1px alternating white/red rows from the bottom, extending to
        // virtualHeight so taller-than-visible rows get clipped by the bar
        let startY = offset
        let endY = startY + virtualHeight
        var row = 0
        var y = startY
        while y < endY {
            if y >= 0 && y < top {
                let color: NSColor = (row % 2 == 0) ? .white : .red
                color.setFill()
                NSRect(x: 0, y: y, width: w, height: 1).fill()
            }
            y += 1
            row += 1
        }

        // Readout so the user can report the numbers
        let text = String(format: "H:%.0f O:%.0f", virtualHeight, offset)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        text.draw(at: NSPoint(x: 2, y: top - 11), withAttributes: attrs)
    }

}

final class CalibrationWidget: NSObject, PKWidget {

    static var identifier: String = "CalibrationWidget"
    var customizationLabel: String = "Calibration"
    var view: NSView!

    private let gridView = CalibrationGridView(frame: .zero)
    private var hotKeys: [EventHotKeyRef?] = []

    /// The widget instance actually being displayed by Pock (not a throwaway
    /// palette instance). Hotkey events are routed to this instance.
    private static weak var current: CalibrationWidget?
    private static var handlerInstalled = false

    var imageForCustomization: NSImage {
        return NSImage(size: NSSize(width: 40, height: 40), flipped: false) { rect in
            for i in 0..<8 {
                (i % 2 == 0 ? NSColor.white : NSColor.red).setFill()
                NSRect(x: 0, y: rect.height - CGFloat(i + 1), width: rect.width, height: 1).fill()
            }
            return true
        }
    }

    override required init() {
        super.init()
        self.view = gridView
    }

    func initialize() {
        let defaults = UserDefaults.standard
        gridView.virtualHeight = CGFloat(defaults.double(forKey: "CalibrationHeight").clamped(to: 10...100, fallback: 30))
        gridView.offset = CGFloat(defaults.double(forKey: "CalibrationOffset").clamped(to: -30...30, fallback: 0))
        CalibrationWidget.installHandler()
        registerHotKeys()
        CalibrationWidget.current = self
        gridView.needsDisplay = true
    }

    func viewDidAppear() {
        CalibrationWidget.current = self
        gridView.needsDisplay = true
    }

    func viewDidDisappear() { }

    // MARK: Hotkeys - Option+Up/Down = move grid, Option+Left/Right = height

    private static func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let result = GetEventParameter(event,
                                           EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID),
                                           nil,
                                           MemoryLayout<EventHotKeyID>.size,
                                           nil,
                                           &hotKeyID)
            guard result == noErr else { return result }
            DispatchQueue.main.async {
                CalibrationWidget.current?.handleKey(Int(hotKeyID.id))
            }
            return noErr
        }, 1, &eventType, nil, nil)
        if status != noErr {
            NSLog("[Calibration]: Failed to install hotkey handler: \(status)")
        }
    }

    private func registerHotKeys() {
        let signature = OSType(0x43414C42) // 'CALB'
        let keys: [(UInt32, Int)] = [
            (UInt32(kVK_UpArrow), 1),
            (UInt32(kVK_DownArrow), 2),
            (UInt32(kVK_LeftArrow), 3),
            (UInt32(kVK_RightArrow), 4)
        ]
        for (keyCode, id) in keys {
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: signature, id: UInt32(id))
            let reg = RegisterEventHotKey(keyCode, UInt32(optionKey), hotKeyID, GetApplicationEventTarget(), 0, &ref)
            if reg != noErr {
                NSLog("[Calibration]: Failed to register key \(id): \(reg)")
            }
            hotKeys.append(ref)
        }
    }

    private func handleKey(_ id: Int) {
        NSLog("[Calibration]: key \(id) received (H:\(gridView.virtualHeight) O:\(gridView.offset)) current=self:\(CalibrationWidget.current === self)")
        switch id {
        case 1: gridView.offset += 1          // Option+Up: move grid up
        case 2: gridView.offset -= 1          // Option+Down: move grid down
        case 3: gridView.virtualHeight -= 1   // Option+Left: shorter grid
        case 4: gridView.virtualHeight += 1   // Option+Right: taller grid
        default: return
        }
        gridView.virtualHeight = gridView.virtualHeight.clamped(to: 10...100, fallback: 30)
        gridView.offset = gridView.offset.clamped(to: -30...30, fallback: 0)
        UserDefaults.standard.set(Double(gridView.virtualHeight), forKey: "CalibrationHeight")
        UserDefaults.standard.set(Double(gridView.offset), forKey: "CalibrationOffset")
        gridView.needsDisplay = true
    }

}

extension Double {
    func clamped(to range: ClosedRange<Double>, fallback: Double) -> Double {
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
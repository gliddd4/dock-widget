//
//  main.swift
//  CornerDock
//
//  Hover the bottom-right corner of the screen to reveal the Trash,
//  the bottom-left corner to reveal Downloads. Slides up from the
//  corner with an opacity fade; click to open in Finder.
//

import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()

// UI/PopupPanel.swift
import AppKit
import SwiftUI

/// Hosts the card's SwiftUI view and accepts the first mouse click even when
/// the app is inactive. Without this, a single click on a grade button in a
/// background (non-key) panel would be swallowed just to focus the panel, so
/// the user would have to click twice. We want the card to be fully operable
/// with one click while never stealing focus from whatever they're doing.
final class PopupHostingView<Content: View>: NSHostingView<Content> {
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class PopupPanel: NSPanel {

  init(contentView: NSView, size: NSSize = NSSize(width: 360, height: 220)) {
    let rect = NSRect(origin: .zero, size: size)
    super.init(
      contentRect: rect,
      styleMask: [.nonactivatingPanel, .borderless],
      backing: .buffered,
      defer: false
    )
    self.isFloatingPanel = true
    self.hidesOnDeactivate = false
    self.level = .floating
    self.backgroundColor = .clear
    self.hasShadow = true
    self.isOpaque = false
    self.isMovableByWindowBackground = false
    self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    self.contentView = contentView
  }
}

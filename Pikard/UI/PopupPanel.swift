// UI/PopupPanel.swift
import AppKit

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

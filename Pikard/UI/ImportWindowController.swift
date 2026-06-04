import AppKit
import SwiftUI

final class ImportWindowController: NSWindowController, NSWindowDelegate {

  private let appState: AppState
  private let onWindowClose: () -> Void

  init(appState: AppState, onWindowClose: @escaping () -> Void) {
    self.appState = appState
    self.onWindowClose = onWindowClose

    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
      styleMask: [.titled, .closable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = "Import deck"
    window.center()
    window.isReleasedWhenClosed = false  // we manage lifetime

    super.init(window: window)
    window.delegate = self

    let root = ImportWindowView(
      appState: appState,
      onClose: { [weak self] in self?.close() }
    )
    window.contentView = NSHostingView(rootView: root)
  }

  required init?(coder: NSCoder) { fatalError("not implemented") }

  func show() {
    NSApp.activate(ignoringOtherApps: true)
    window?.makeKeyAndOrderFront(nil)
  }

  func windowWillClose(_ notification: Notification) {
    onWindowClose()
  }
}

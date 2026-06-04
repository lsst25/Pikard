import AppKit
import SwiftUI

final class DeckManagerWindowController: NSWindowController, NSWindowDelegate {

  private let appState: AppState
  private let onWindowClose: () -> Void

  init(appState: AppState, onWindowClose: @escaping () -> Void = {}) {
    self.appState = appState
    self.onWindowClose = onWindowClose

    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 700, height: 480),
      styleMask: [.titled, .closable, .resizable, .miniaturizable],
      backing: .buffered,
      defer: false
    )
    window.title = "Manage Decks"
    window.center()
    window.isReleasedWhenClosed = false

    super.init(window: window)
    window.delegate = self

    window.contentView = NSHostingView(rootView: DeckManagerView(appState: appState))
  }

  required init?(coder: NSCoder) { fatalError("not implemented") }

  func show() {
    NSApp.activate(ignoringOtherApps: true)
    window?.makeKeyAndOrderFront(nil)
  }

  func windowWillClose(_ notification: Notification) {
    appState.flush()  // persist any debounced edits before the window goes away
    onWindowClose()
  }
}

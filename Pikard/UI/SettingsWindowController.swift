import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController, NSWindowDelegate {

  private let appState: AppState
  private let onWindowClose: () -> Void

  init(appState: AppState, onWindowClose: @escaping () -> Void = {}) {
    self.appState = appState
    self.onWindowClose = onWindowClose

    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 440, height: 640),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    window.title = "Pikard Settings"
    window.center()
    window.isReleasedWhenClosed = false

    super.init(window: window)
    window.delegate = self

    window.contentView = NSHostingView(rootView: SettingsView(appState: appState))
  }

  required init?(coder: NSCoder) { fatalError("not implemented") }

  func show() {
    NSApp.activate(ignoringOtherApps: true)
    window?.makeKeyAndOrderFront(nil)
  }

  func windowWillClose(_ notification: Notification) {
    appState.flush()
    onWindowClose()
  }
}

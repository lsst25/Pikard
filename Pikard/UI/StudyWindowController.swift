import AppKit
import SwiftUI

/// Hosts the study window — a normal, focusable window (unlike the popup panel)
/// so the user can flip through cards at their own pace with the keyboard.
final class StudyWindowController: NSWindowController, NSWindowDelegate {

  private let appState: AppState
  private let onWindowClose: () -> Void

  init(appState: AppState, onWindowClose: @escaping () -> Void = {}) {
    self.appState = appState
    self.onWindowClose = onWindowClose

    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 460, height: 460),
      styleMask: [.titled, .closable, .resizable, .miniaturizable],
      backing: .buffered,
      defer: false
    )
    window.title = "Study"
    window.center()
    window.isReleasedWhenClosed = false

    super.init(window: window)
    window.delegate = self

    window.contentView = NSHostingView(rootView: StudyView(appState: appState))
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

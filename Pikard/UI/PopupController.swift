// UI/PopupController.swift
import AppKit
import SwiftUI

@MainActor
final class PopupController {

  private var panel: PopupPanel?
  private var globalClickMonitor: Any?
  private var previousFrontmostBundleId: String?
  private var isDismissing = false

  var isVisible: Bool { panel?.isVisible == true }

  // MARK: Card popup

  func show(
    card: Card,
    promptSide: Deck.PromptSide = .front,
    corner: AppSettings.PopupCorner = .topRight,
    onGrade: @escaping (Grade) -> Void,
    onDismiss: @escaping () -> Void = {}
  ) {
    if isVisible { return }

    let root = CardView(
      card: card,
      promptSide: promptSide,
      onGrade: { [weak self] grade in
        onGrade(grade)
        self?.dismiss()
      },
      onDismiss: { [weak self] in
        onDismiss()
        self?.dismiss()
      }
    )
    present(
      view: root,
      size: NSSize(width: 360, height: 220),
      corner: corner,
      onOutsideClick: { onDismiss() })
  }

  // MARK: Empty-state popup

  func showEmptyState(
    message: String,
    corner: AppSettings.PopupCorner = .topRight,
    onDismiss: @escaping () -> Void = {}
  ) {
    if isVisible { return }

    let view = EmptyStateView(
      message: message,
      onDismiss: { [weak self] in
        onDismiss()
        self?.dismiss()
      })
    present(
      view: view,
      size: NSSize(width: 360, height: 140),
      corner: corner,
      onOutsideClick: { onDismiss() })
  }

  // MARK: Dismiss

  func dismiss() {
    // Idempotent: a second trigger (e.g. Esc during the exit animation, or an
    // outside-click landing in the same window) is a no-op.
    guard !isDismissing, let panel else { return }
    isDismissing = true

    if let monitor = globalClickMonitor {
      NSEvent.removeMonitor(monitor)
      globalClickMonitor = nil
    }
    animateOut(panel) { [weak self] in
      self?.panel = nil
      self?.isDismissing = false
      self?.restorePreviousApp()
    }
  }

  // MARK: Presentation plumbing

  private func present<Content: View>(
    view: Content,
    size: NSSize,
    corner: AppSettings.PopupCorner,
    onOutsideClick: @escaping () -> Void
  ) {
    // Remember which app was frontmost, then activate ourselves so the panel
    // can receive keystrokes (Space to flip, arrows to grade).
    previousFrontmostBundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    NSApp.activate(ignoringOtherApps: true)

    let host = NSHostingView(rootView: view)
    host.frame = NSRect(origin: .zero, size: size)

    let newPanel = PopupPanel(contentView: host, size: size)
    position(newPanel, corner: corner)
    animateIn(newPanel)
    newPanel.makeKeyAndOrderFront(nil)  // become key so SwiftUI gets key events
    panel = newPanel

    globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown]
    ) { [weak self] _ in
      onOutsideClick()
      self?.dismiss()
    }
  }

  private func restorePreviousApp() {
    defer { previousFrontmostBundleId = nil }
    guard let bid = previousFrontmostBundleId,
      let prev = NSRunningApplication.runningApplications(withBundleIdentifier: bid).first
    else { return }
    prev.activate()
  }

  private func position(_ panel: PopupPanel, corner: AppSettings.PopupCorner) {
    guard let screen = NSScreen.main else { return }
    let frame = screen.visibleFrame
    let size = panel.frame.size
    let inset: CGFloat = 20

    let x: CGFloat
    let y: CGFloat
    switch corner {
    case .topLeft:
      x = frame.minX + inset
      y = frame.maxY - size.height - inset
    case .topRight:
      x = frame.maxX - size.width - inset
      y = frame.maxY - size.height - inset
    case .bottomLeft:
      x = frame.minX + inset
      y = frame.minY + inset
    case .bottomRight:
      x = frame.maxX - size.width - inset
      y = frame.minY + inset
    }
    panel.setFrameOrigin(NSPoint(x: x, y: y))
  }

  private func animateIn(_ panel: PopupPanel) {
    let target = panel.frame
    let startFrame = target.offsetBy(dx: 0, dy: 20)
    panel.alphaValue = 0
    panel.setFrame(startFrame, display: false)
    panel.orderFrontRegardless()

    NSAnimationContext.runAnimationGroup { ctx in
      ctx.duration = 0.25
      ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
      panel.animator().setFrame(target, display: true)
      panel.animator().alphaValue = 1
    }
  }

  private func animateOut(_ panel: PopupPanel, then completion: @escaping () -> Void) {
    let target = panel.frame.offsetBy(dx: 0, dy: 20)
    NSAnimationContext.runAnimationGroup(
      { ctx in
        ctx.duration = 0.18
        ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
        panel.animator().setFrame(target, display: true)
        panel.animator().alphaValue = 0
      },
      completionHandler: {
        panel.orderOut(nil)
        completion()
      })
  }
}

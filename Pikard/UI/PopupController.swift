// UI/PopupController.swift
import AppKit
import SwiftUI

@MainActor
final class PopupController {

  private var panel: PopupPanel?
  private var globalClickMonitor: Any?
  private var isDismissing = false

  /// The hosting view of a card popup, kept so a batch run can swap in the next
  /// card without tearing the panel down. Nil for the empty-state popup.
  private var cardHost: PopupHostingView<CardView>?
  /// What an outside click should do. Re-pointed on every `replace` so the click
  /// always grades the card currently on screen, not the one the panel opened with.
  private var outsideClickHandler: (() -> Void)?

  var isVisible: Bool { panel?.isVisible == true }

  private static let cardSize = NSSize(width: 360, height: 220)

  // MARK: Card popup

  /// Show a card. `onGrade` does **not** close the popup — the caller decides
  /// whether to `replace` it with the next card of a batch or `dismiss` it.
  /// `onDismiss` (the ✕ button, or an outside click) always closes it.
  func show(
    card: Card,
    deckName: String,
    promptSide: Deck.PromptSide = .front,
    corner: AppSettings.PopupCorner = .topRight,
    boxCount: Int = AppSettings.defaultBoxIntervals.count,
    dismissOnOutsideClick: Bool = false,
    batchLabel: String? = nil,
    onGrade: @escaping (Grade) -> Void,
    onDismiss: @escaping () -> Void = {}
  ) {
    if isVisible { return }

    let host = PopupHostingView(
      rootView: cardView(
        card: card,
        deckName: deckName,
        promptSide: promptSide,
        boxCount: boxCount,
        batchLabel: batchLabel,
        onGrade: onGrade,
        onDismiss: onDismiss))
    cardHost = host
    outsideClickHandler = dismissOnOutsideClick ? onDismiss : nil

    present(
      host: host,
      size: Self.cardSize,
      corner: corner,
      watchOutsideClicks: dismissOnOutsideClick)
  }

  /// Swap the card shown by an already-visible card popup (batch mode). Returns
  /// false when there is no card popup on screen to replace, in which case the
  /// caller should fall back to `show`.
  @discardableResult
  func replace(
    card: Card,
    deckName: String,
    promptSide: Deck.PromptSide = .front,
    boxCount: Int = AppSettings.defaultBoxIntervals.count,
    dismissOnOutsideClick: Bool = false,
    batchLabel: String? = nil,
    onGrade: @escaping (Grade) -> Void,
    onDismiss: @escaping () -> Void = {}
  ) -> Bool {
    guard !isDismissing, let panel, panel.isVisible, let host = cardHost else {
      return false
    }

    let next = cardView(
      card: card,
      deckName: deckName,
      promptSide: promptSide,
      boxCount: boxCount,
      batchLabel: batchLabel,
      onGrade: onGrade,
      onDismiss: onDismiss)
    outsideClickHandler = dismissOnOutsideClick ? onDismiss : nil

    // Brief cross-fade so the swap reads as "next card", not as a mis-click.
    fadeOut(panel) { [weak self] in
      // The panel may have been dismissed during the fade — don't resurrect it.
      guard let self, self.panel === panel, !self.isDismissing else { return }
      host.rootView = next  // CardView resets its flip on the new card.id
      self.fadeIn(panel)
    }
    return true
  }

  private func cardView(
    card: Card,
    deckName: String,
    promptSide: Deck.PromptSide,
    boxCount: Int,
    batchLabel: String?,
    onGrade: @escaping (Grade) -> Void,
    onDismiss: @escaping () -> Void
  ) -> CardView {
    CardView(
      card: card,
      deckName: deckName,
      promptSide: promptSide,
      boxCount: boxCount,
      batchLabel: batchLabel,
      onGrade: onGrade,
      onDismiss: { [weak self] in
        onDismiss()
        self?.dismiss()
      }
    )
  }

  // MARK: Empty-state popup

  func showEmptyState(
    message: String,
    corner: AppSettings.PopupCorner = .topRight,
    dismissOnOutsideClick: Bool = false,
    onDismiss: @escaping () -> Void = {}
  ) {
    if isVisible { return }

    let host = PopupHostingView(
      rootView: EmptyStateView(
        message: message,
        onDismiss: { [weak self] in
          onDismiss()
          self?.dismiss()
        }))
    outsideClickHandler = dismissOnOutsideClick ? onDismiss : nil

    present(
      host: host,
      size: NSSize(width: 360, height: 140),
      corner: corner,
      watchOutsideClicks: dismissOnOutsideClick)
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
    outsideClickHandler = nil
    animateOut(panel) { [weak self] in
      self?.panel = nil
      self?.cardHost = nil
      self?.isDismissing = false
    }
  }

  // MARK: Presentation plumbing

  private func present(
    host: NSView,
    size: NSSize,
    corner: AppSettings.PopupCorner,
    watchOutsideClicks: Bool
  ) {
    // Show the card on top of everything without activating the app or taking
    // key status, so it never interrupts whatever the user is typing. It's
    // operated entirely with the mouse; PopupHostingView makes a single click
    // land on the buttons even though the app stays inactive.
    host.frame = NSRect(origin: .zero, size: size)

    let newPanel = PopupPanel(contentView: host, size: size)
    position(newPanel, corner: corner)
    animateIn(newPanel)  // orders the panel front (orderFrontRegardless), no focus change
    panel = newPanel

    // Only watch for outside clicks when the setting opts in. Otherwise the card
    // stays put until it's graded or explicitly dismissed.
    if watchOutsideClicks {
      globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
        matching: [.leftMouseDown, .rightMouseDown]
      ) { [weak self] _ in
        self?.outsideClickHandler?()
        self?.dismiss()
      }
    }
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

  private func fadeOut(_ panel: PopupPanel, then completion: @escaping () -> Void) {
    NSAnimationContext.runAnimationGroup(
      { ctx in
        ctx.duration = 0.09
        panel.animator().alphaValue = 0
      },
      completionHandler: completion)
  }

  private func fadeIn(_ panel: PopupPanel) {
    NSAnimationContext.runAnimationGroup { ctx in
      ctx.duration = 0.14
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

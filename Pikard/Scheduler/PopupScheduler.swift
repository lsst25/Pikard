import AppKit
import Combine
import Foundation

/// Drives the popup cadence. At all times it holds exactly one pending one-shot
/// timer pointed at the next due moment. Every fire re-checks all gates
/// (running, paused, quiet hours, popup-in-flight) before showing a card and
/// then reschedules itself.
@MainActor
final class PopupScheduler: ObservableObject {

  // MARK: Dependencies
  private let appState: AppState
  private let popup: PopupController

  // MARK: Published state
  @Published private(set) var isRunning = false
  @Published private(set) var nextFire: Date?
  @Published var pausedUntil: Date?

  // MARK: Tuning
  var jitterFraction: Double = 0.2
  private let minimumDelay: TimeInterval = 5

  // MARK: GCD
  private var timer: DispatchSourceTimer?

  init(appState: AppState, popup: PopupController) {
    self.appState = appState
    self.popup = popup

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(workspaceDidWake),
      name: NSWorkspace.didWakeNotification,
      object: nil)
  }

  deinit {
    timer?.setEventHandler(handler: nil)
    timer?.cancel()
    NotificationCenter.default.removeObserver(self)
  }

  // MARK: Control

  func start() {
    guard !isRunning else { return }
    isRunning = true
    scheduleNext()
  }

  func stop() {
    isRunning = false
    timer?.cancel()
    timer = nil
    nextFire = nil
  }

  /// Pause for a fixed interval (e.g. "skip next hour").
  func pause(for interval: TimeInterval) {
    pausedUntil = Date().addingTimeInterval(interval)
    scheduleNext()
  }

  func resume() {
    pausedUntil = nil
    scheduleNext()
  }

  /// Force a card to appear as soon as possible (ignores the interval, honours
  /// the empty-corpus path).
  func fireNow() {
    timer?.cancel()
    timer = nil
    fireOnMain()
  }

  /// Recompute the next deadline now (e.g. after the user changes the interval).
  func fireNowOrReschedule() {
    scheduleNext()
  }

  @objc private func workspaceDidWake() {
    // GCD timers don't catch up after sleep; fire immediately if we're overdue.
    Task { @MainActor in
      guard self.isRunning else { return }
      if let next = self.nextFire, next <= Date() {
        self.fireNow()
      }
    }
  }
}

extension PopupScheduler {

  private func scheduleNext() {
    // Tear down the old source: clear its handler first so a fire already in
    // flight can't sneak through after cancel, then cancel.
    timer?.setEventHandler(handler: nil)
    timer?.cancel()
    timer = nil
    nextFire = nil
    guard isRunning else { return }

    let now = Date()
    let delay = computeDelay(from: now)
    nextFire = now.addingTimeInterval(delay)

    // Each source is created fresh and resumed exactly once. The whole method
    // runs on the main actor, so no two scheduleNext() calls interleave.
    let t = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
    t.schedule(deadline: .now() + delay, repeating: .never, leeway: .seconds(5))
    t.setEventHandler { [weak self] in
      Task { @MainActor in self?.fireOnMain() }
    }
    timer = t  // track before resuming
    t.resume()
  }

  private func computeDelay(from now: Date) -> TimeInterval {
    // Paused: sleep until the pause expires.
    if let paused = pausedUntil, paused > now {
      return paused.timeIntervalSince(now) + 1
    }
    // Quiet hours: sleep until the window ends (plus a small grace).
    if appState.settings.isQuietHour(at: now) {
      return appState.settings.secondsUntilQuietEnds(now: now) + 30
    }
    // Base interval + jitter band.
    let base = appState.settings.intervalMinutes * 60
    let jitter = base * jitterFraction * Double.random(in: -1...1)
    return max(minimumDelay, base + jitter)
  }

  private func fireOnMain() {
    // Re-check every gate; state may have changed during the wait.
    guard isRunning else { return }
    if let paused = pausedUntil, paused > Date() {
      scheduleNext()
      return
    }
    if appState.settings.isQuietHour(at: Date()) {
      scheduleNext()
      return
    }
    if popup.isVisible {
      // Don't pile up popups; try again after one interval.
      scheduleNext()
      return
    }

    if let next = SRSAlgorithm.selectNextCard(decks: appState.decks) {
      let side =
        appState.decks.first { $0.id == next.deckId }?.promptSide ?? .front
      popup.show(
        card: next.card,
        promptSide: side,
        corner: appState.settings.popupCorner,
        onGrade: { [weak self] grade in
          self?.appState.grade(card: next.card, in: next.deckId, as: grade)
          self?.scheduleNext()
        },
        onDismiss: { [weak self] in
          self?.appState.grade(card: next.card, in: next.deckId, as: .neutralDismiss)
          self?.scheduleNext()
        }
      )
    } else {
      // Nothing to show; wait one more interval and try again.
      scheduleNext()
    }
  }
}

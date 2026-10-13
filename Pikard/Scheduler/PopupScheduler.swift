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
  /// How often to re-check while the screen is being shared (no stop event exists).
  private let screenShareRecheckDelay: TimeInterval = 30

  // MARK: GCD
  private var timer: DispatchSourceTimer?

  // MARK: Batch run
  /// Cards still allowed in the run currently on screen (0 = no run in flight).
  private var runRemaining = 0
  /// Total size of the run on screen, for the "2/5" label.
  private var runTotal = 1
  /// Cards already shown in this run, so a re-scheduled card can't come back
  /// around within the same batch.
  private var runShown: Set<UUID> = []

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
    // Screen sharing/recording: there's no "stopped" notification, so poll.
    if ScreenShareDetector.isScreenBeingCaptured {
      return screenShareRecheckDelay
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
    // Never pop a card while the screen is being shared/recorded.
    if ScreenShareDetector.isScreenBeingCaptured {
      scheduleNext()
      return
    }
    if popup.isVisible {
      // Don't pile up popups; try again after one interval.
      scheduleNext()
      return
    }

    if !showCardRun() {
      // Nothing to show; wait one more interval and try again.
      scheduleNext()
    }
  }
}

// MARK: - Card runs (batching)

extension PopupScheduler {

  /// Show a card now and, when `batchSize > 1`, keep swapping in the next due
  /// card as each one is graded Known / Still learning. A neutral dismissal (the
  /// ✕ or an outside click) ends the run early, as does running out of due cards.
  /// The cadence is reset from the moment the run finishes.
  ///
  /// Returns false when there was nothing at all to show, letting the caller
  /// decide what to do instead (reschedule, or show the empty state).
  @discardableResult
  func showCardRun() -> Bool {
    // A popup already on screen counts as "showing something".
    guard !popup.isVisible else { return true }

    guard
      let first = SRSAlgorithm.selectNextCard(
        decks: appState.decks,
        fallbackToUpcoming: appState.settings.showUpcomingWhenNothingDue)
    else {
      endRun(reschedule: false)
      return false
    }

    // Cap the run at what's actually due, so the "2/5" counter never promises
    // cards the corpus can't deliver. (`first` may itself be a not-yet-due
    // fallback card, in which case the run is just that one card.)
    runTotal = min(
      appState.settings.cardsPerRun,
      max(1, SRSAlgorithm.dueCount(decks: appState.decks)))
    runRemaining = runTotal
    runShown = []
    present(first, replacingPanel: false)
    return true
  }

  private func present(_ next: (card: Card, deckId: UUID), replacingPanel: Bool) {
    runRemaining -= 1
    runShown.insert(next.card.id)

    let deck = appState.decks.first { $0.id == next.deckId }
    let side = deck?.promptSide ?? .front
    let boxCount = appState.settings.effectiveBoxIntervals.count
    // "2/5" only while batching; a single-card run keeps the plain card.
    let label = runTotal > 1 ? "\(runShown.count)/\(runTotal)" : nil

    let onGrade: (Grade) -> Void = { [weak self] grade in
      guard let self else { return }
      appState.grade(card: next.card, in: next.deckId, as: grade)
      advanceRun()
    }
    // Neutral dismissal stops the batch. The popup closes itself.
    let onDismiss: () -> Void = { [weak self] in
      guard let self else { return }
      appState.grade(card: next.card, in: next.deckId, as: .neutralDismiss)
      endRun(reschedule: true)
    }

    if replacingPanel {
      let replaced = popup.replace(
        card: next.card,
        deckName: deck?.name ?? "",
        promptSide: side,
        boxCount: boxCount,
        dismissOnOutsideClick: appState.settings.dismissOnOutsideClick,
        batchLabel: label,
        onGrade: onGrade,
        onDismiss: onDismiss)
      // The panel went away under us (e.g. dismissed mid-animation): stop here.
      if !replaced { endRun(reschedule: true) }
    } else {
      popup.show(
        card: next.card,
        deckName: deck?.name ?? "",
        promptSide: side,
        corner: appState.settings.popupCorner,
        boxCount: boxCount,
        dismissOnOutsideClick: appState.settings.dismissOnOutsideClick,
        batchLabel: label,
        onGrade: onGrade,
        onDismiss: onDismiss)
    }
  }

  /// Called after a Known / Still-learning grade: pull the next due card into the
  /// same panel, or close it and reset the cadence if the run is over.
  private func advanceRun() {
    // Screen sharing may have started mid-run; don't put another card on a
    // shared screen just because the previous one was already up.
    guard !ScreenShareDetector.isScreenBeingCaptured,
      runRemaining > 0,
      let next = SRSAlgorithm.selectNextDueCard(
        decks: appState.decks, excluding: runShown)
    else {
      popup.dismiss()
      endRun(reschedule: true)
      return
    }
    present(next, replacingPanel: true)
  }

  private func endRun(reschedule: Bool) {
    runRemaining = 0
    runTotal = 1
    runShown = []
    if reschedule { scheduleNext() }
  }
}

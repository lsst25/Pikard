import Foundation

enum SRSAlgorithm {

  /// Intervals per box, in seconds, used when the caller passes none.
  /// The live app passes `AppSettings.effectiveBoxIntervals` instead.
  static let defaultIntervals: [TimeInterval] = AppSettings.defaultBoxIntervals

  /// How long a Still-learning card waits before coming back, regardless of box.
  static let stillLearningDelay: TimeInterval = 2 * 60

  /// How long a neutrally dismissed card waits before coming back, regardless of box.
  static let neutralDismissDelay: TimeInterval = 10 * 60

  /// `box` clamped into the ladder `intervals` describes. A card can sit in a
  /// box that no longer exists after the user removes boxes; it is treated as
  /// being in the last remaining box.
  static func clampedBox(_ box: Int, intervals: [TimeInterval]) -> Int {
    min(max(0, intervals.count - 1), max(0, box))
  }

  /// Returns the next `SRSState` for a card after the user grades it.
  /// Pure: same inputs always return the same output (given a fixed `now`).
  static func grade(
    _ state: SRSState,
    as grade: Grade,
    intervals: [TimeInterval] = defaultIntervals,
    now: Date = Date()
  ) -> SRSState {
    let ladder = intervals.isEmpty ? defaultIntervals : intervals
    let current = clampedBox(state.box, intervals: ladder)

    var next = state
    next.timesSeen += 1
    next.lastGradedAt = now

    switch grade {
    case .known:
      next.box = min(ladder.count - 1, current + 1)
      next.dueAt = now.addingTimeInterval(ladder[next.box])
      next.timesKnown += 1
    case .stillLearning:
      next.box = max(0, current - 1)
      next.dueAt = now.addingTimeInterval(stillLearningDelay)
    case .neutralDismiss:
      next.box = current
      next.dueAt = now.addingTimeInterval(neutralDismissDelay)
    }
    return next
  }
}

extension SRSAlgorithm {

  /// Return the next card to show, plus the deck it belongs to.
  ///
  /// With `fallbackToUpcoming` (the default) a not-yet-due card is returned when
  /// nothing is due, so the user is never told "nothing". With it off, nil means
  /// "nothing is due right now" — the same contract as `selectNextDueCard`.
  /// Returns nil if the corpus is empty.
  static func selectNextCard(
    decks: [Deck],
    fallbackToUpcoming: Bool = true,
    now: Date = Date()
  ) -> (card: Card, deckId: UUID)? {

    if let due = selectNextDueCard(decks: decks, now: now) { return due }
    guard fallbackToUpcoming else { return nil }

    // Nothing due; pick the soonest-upcoming card so the user is never told "nothing".
    let pool = activePool(decks)
    guard let soonest = pool.min(by: { $0.1.srs.dueAt < $1.1.srs.dueAt }) else {
      return nil
    }
    return (soonest.1, soonest.0.id)
  }

  /// Return the most-overdue card that is *actually* due, skipping any card in
  /// `excluding`. Unlike `selectNextCard` this has no soonest-upcoming fallback:
  /// nil means "nothing left to review right now", which is what lets a batch
  /// run stop instead of re-showing cards that aren't due yet.
  static func selectNextDueCard(
    decks: [Deck],
    excluding: Set<UUID> = [],
    now: Date = Date()
  ) -> (card: Card, deckId: UUID)? {

    // Cards already due, oldest first.
    let due =
      activePool(decks)
      .filter { $0.1.srs.dueAt <= now && !excluding.contains($0.1.id) }
      .sorted { $0.1.srs.dueAt < $1.1.srs.dueAt }

    guard let oldest = due.first?.1.srs.dueAt else { return nil }
    // Take every card sharing the oldest dueAt (tie band), pick one at random.
    let ties = due.filter { $0.1.srs.dueAt == oldest }
    let pick = ties.randomElement() ?? due[0]
    return (pick.1, pick.0.id)
  }

  /// When the next card in an active deck becomes due. Nil for an empty corpus.
  /// In the past when something is already due.
  static func nextDueDate(decks: [Deck]) -> Date? {
    activePool(decks).map { $0.1.srs.dueAt }.min()
  }

  /// Flatten active decks into (deck, card) pairs.
  private static func activePool(_ decks: [Deck]) -> [(Deck, Card)] {
    decks
      .filter { $0.isActive }
      .flatMap { deck in deck.cards.map { (deck, $0) } }
  }

  /// Count of cards from active decks with `dueAt <= now`.
  static func dueCount(decks: [Deck], now: Date = Date()) -> Int {
    decks.lazy
      .filter { $0.isActive }
      .flatMap { $0.cards }
      .filter { $0.srs.dueAt <= now }
      .count
  }
}

import Foundation

enum SRSAlgorithm {

  /// Intervals per box, in seconds. Box 0 → 5 min, box 5 → 7 days.
  static let intervals: [TimeInterval] = [
    5 * 60,
    30 * 60,
    4 * 3600,
    24 * 3600,
    3 * 24 * 3600,
    7 * 24 * 3600,
  ]

  /// Returns the next `SRSState` for a card after the user grades it.
  /// Pure: same inputs always return the same output (given a fixed `now`).
  static func grade(
    _ state: SRSState,
    as grade: Grade,
    now: Date = Date()
  ) -> SRSState {
    var next = state
    next.timesSeen += 1
    next.lastGradedAt = now

    switch grade {
    case .known:
      next.box = min(intervals.count - 1, state.box + 1)
      next.dueAt = now.addingTimeInterval(intervals[next.box])
      next.timesKnown += 1
    case .stillLearning:
      next.box = max(0, state.box - 1)
      next.dueAt = now.addingTimeInterval(2 * 60)
    case .neutralDismiss:
      next.dueAt = now.addingTimeInterval(10 * 60)
    }
    return next
  }
}

extension SRSAlgorithm {

  /// Return the next card to show, plus the deck it belongs to.
  /// Returns nil if the corpus is empty.
  static func selectNextCard(
    decks: [Deck],
    now: Date = Date()
  ) -> (card: Card, deckId: UUID)? {

    if let due = selectNextDueCard(decks: decks, now: now) { return due }

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

import Combine
import Foundation

/// What a study session draws from: every deck, or one specific deck.
/// Unlike the passive popup rotation, study deliberately ignores `isActive`
/// — the user chose to open the window, so they can study any deck.
enum StudyScope: Equatable, Hashable {
  case allDecks
  case deck(UUID)
}

/// One position in a study queue. Holds card *identity* only; the live card
/// (and its current SRS box) is re-fetched from `AppState` each time it's shown
/// so grades made during the session are reflected immediately.
struct StudyItem: Equatable, Identifiable {
  let deckId: UUID
  let cardId: UUID
  let deckName: String
  /// Which face shows first, with `.random` already resolved once at build time
  /// so flipping back and forth doesn't reshuffle the card.
  let promptIsFront: Bool

  var id: UUID { cardId }
}

extension StudySession {

  /// Build the ordered queue for a scope. Pure and deterministic (aside from
  /// `.random` prompt sides). Ordered by due date ascending, so the most-overdue
  /// cards come first and not-yet-due cards trail by soonest due — the same
  /// "review what's most due" priority the popup uses, but as a full traversable
  /// list instead of a single pick.
  nonisolated static func buildQueue(
    decks: [Deck],
    scope: StudyScope
  ) -> [StudyItem] {
    let chosen: [Deck]
    switch scope {
    case .allDecks: chosen = decks
    case .deck(let id): chosen = decks.filter { $0.id == id }
    }

    let pairs: [(item: StudyItem, dueAt: Date)] = chosen.flatMap { deck in
      deck.cards.map { card -> (StudyItem, Date) in
        let promptIsFront: Bool
        switch deck.promptSide {
        case .front: promptIsFront = true
        case .back: promptIsFront = false
        case .random: promptIsFront = Bool.random()
        }
        let item = StudyItem(
          deckId: deck.id,
          cardId: card.id,
          deckName: deck.name,
          promptIsFront: promptIsFront)
        return (item, card.srs.dueAt)
      }
    }

    return pairs.sorted { $0.dueAt < $1.dueAt }.map(\.item)
  }
}

/// Drives a single study session: an ordered queue of cards the user flips
/// through and grades. Grading routes through `AppState.grade`, so it updates
/// the very same SRS state the popup does. The queue is a snapshot — built on
/// open, scope change, or restart — so grading a card never reorders it out
/// from under the user; only an explicit "Study again" reshuffles by due date.
@MainActor
final class StudySession: ObservableObject {

  private let appState: AppState

  @Published private(set) var scope: StudyScope
  @Published private(set) var queue: [StudyItem] = []
  @Published private(set) var index: Int = 0
  @Published private(set) var showingAnswer = false
  /// True once the final card in the queue has been graded — shows the summary.
  @Published private(set) var finished = false
  /// Distinct cards graded this session (for the summary count).
  @Published private(set) var gradedCardIds: Set<UUID> = []

  init(appState: AppState, scope: StudyScope = .allDecks) {
    self.appState = appState
    self.scope = scope
    // didSet doesn't fire from an initialiser, so build explicitly.
    queue = Self.buildQueue(decks: appState.decks, scope: scope)
  }

  // MARK: Derived state

  var currentItem: StudyItem? {
    queue.indices.contains(index) ? queue[index] : nil
  }

  /// The live card behind the current position, re-fetched so its SRS box is
  /// current. Nil if the card was deleted elsewhere (e.g. in the deck manager).
  var currentCard: Card? {
    guard let item = currentItem else { return nil }
    return appState.decks.first { $0.id == item.deckId }?
      .cards.first { $0.id == item.cardId }
  }

  var count: Int { queue.count }
  var position: Int { queue.isEmpty ? 0 : index + 1 }
  var isAtStart: Bool { index <= 0 }
  var isAtEnd: Bool { index >= queue.count - 1 }
  var isEmpty: Bool { queue.isEmpty }

  // MARK: Scope

  func setScope(_ newScope: StudyScope) {
    guard newScope != scope else { return }
    scope = newScope
    rebuild()
  }

  /// Rebuild the queue from the current decks/scope and start the count over.
  /// Resetting `gradedCardIds` here keeps the summary's "graded N of M" honest:
  /// M is the new queue's size, so N must only count cards from this queue.
  func rebuild() {
    queue = Self.buildQueue(decks: appState.decks, scope: scope)
    index = 0
    showingAnswer = false
    finished = false
    gradedCardIds = []
  }

  /// Reshuffle by due date and study again (offered on the summary screen).
  /// Cards just graded "known" sink to the back; "still learning" float up.
  func restart() {
    rebuild()
  }

  // MARK: Navigation

  func flip() {
    guard currentCard != nil else { return }
    showingAnswer.toggle()
  }

  func next() { move(by: 1) }
  func previous() { move(by: -1) }

  /// Move past the current position even when its live card is gone (deleted
  /// elsewhere mid-session). Advances if a card follows, otherwise ends the
  /// session — so a missing card is always escapable and never a dead end.
  func skip() {
    if isAtEnd {
      finished = true
    } else {
      move(by: 1)
    }
  }

  private func move(by delta: Int) {
    let target = index + delta
    guard queue.indices.contains(target) else { return }
    index = target
    showingAnswer = false
  }

  // MARK: Grading

  /// Grade the current card — identical effect to grading a popup card — then
  /// advance. Grading the last card ends the session (shows the summary).
  func grade(_ grade: Grade) {
    guard let item = currentItem, let card = currentCard else { return }
    appState.grade(card: card, in: item.deckId, as: grade)
    gradedCardIds.insert(card.id)

    if isAtEnd {
      finished = true
    } else {
      move(by: 1)
    }
  }
}

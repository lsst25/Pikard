//
//  PikardTests.swift
//  PikardTests
//
//  Created by Yuriy Tatar on 23/5/26.
//

import XCTest

@testable import Pikard

final class QuizletParserTests: XCTestCase {

  func test_tabSeparated() {
    let text = "Bonjour\tHello\nMerci\tThanks"
    let cards = QuizletParser.parse(text)
    XCTAssertEqual(cards.count, 2)
    XCTAssertEqual(cards[0].front, "Bonjour")
    XCTAssertEqual(cards[0].back, "Hello")
  }

  func test_commaWhenNoTab() {
    let text = "Bonjour,Hello\nMerci,Thanks"
    let cards = QuizletParser.parse(text)
    XCTAssertEqual(cards.count, 2)
    XCTAssertEqual(cards[1].back, "Thanks")
  }

  func test_semicolonWhenNoTabOrComma() {
    let text = "Bonjour;Hello\nMerci;Thanks"
    let cards = QuizletParser.parse(text)
    XCTAssertEqual(cards.count, 2)
  }

  func test_windowsLineEndings() {
    let text = "Bonjour\tHello\r\nMerci\tThanks"
    let cards = QuizletParser.parse(text)
    XCTAssertEqual(cards.count, 2)
  }

  func test_doubleNewlineRowSeparator() {
    let text = "Bonjour\tHello\n\nMerci\tThanks"
    XCTAssertEqual(QuizletParser.parse(text).count, 2)
  }

  func test_skipsEmptyLines() {
    let text = "\n\nBonjour\tHello\n\n\nMerci\tThanks\n"
    XCTAssertEqual(QuizletParser.parse(text).count, 2)
  }

  func test_trimsWhitespace() {
    let text = "   Bonjour\t  Hello  \n  Merci\t  Thanks  "
    let cards = QuizletParser.parse(text)
    XCTAssertEqual(cards[0].front, "Bonjour")
    XCTAssertEqual(cards[0].back, "Hello")
  }

  func test_joinsOverflowFields() {
    let text = "Bonjour\tHello\tHi\tHey"
    let cards = QuizletParser.parse(text)
    XCTAssertEqual(cards[0].front, "Bonjour")
    XCTAssertEqual(cards[0].back, "Hello — Hi — Hey")
  }

  func test_rejectsMissingBack() {
    let text = "Bonjour\nMerci"
    XCTAssertEqual(QuizletParser.parse(text).count, 0)
  }

  func test_rejectsEmptyBack() {
    let text = "Bonjour\t"
    XCTAssertEqual(QuizletParser.parse(text).count, 0)
  }

  func test_mergeDedupesCaseInsensitively() {
    let existing = [Card(front: "Bonjour", back: "Hello")]
    let incoming = [
      Card(front: "BONJOUR", back: "hello"),
      Card(front: "Merci", back: "Thanks"),
    ]
    let merged = QuizletParser.merge(existing: existing, incoming: incoming)
    XCTAssertEqual(merged.count, 2)
    XCTAssertEqual(merged[1].front, "Merci")
  }
}

final class SRSAlgorithmTests: XCTestCase {

  func test_knownAdvancesBoxAndExtendsDue() {
    let now = Date()
    var state = SRSState()
    state.box = 0

    let next = SRSAlgorithm.grade(state, as: .known, now: now)

    XCTAssertEqual(next.box, 1)
    XCTAssertEqual(next.timesSeen, 1)
    XCTAssertEqual(next.timesKnown, 1)
    XCTAssertEqual(
      next.dueAt.timeIntervalSince(now),
      30 * 60,
      accuracy: 0.001)
  }

  func test_knownCapsAtBoxFive() {
    var state = SRSState()
    state.box = 5
    let next = SRSAlgorithm.grade(state, as: .known, now: Date())
    XCTAssertEqual(next.box, 5)
  }

  func test_stillLearningStepsDown() {
    var state = SRSState()
    state.box = 3
    let next = SRSAlgorithm.grade(state, as: .stillLearning, now: Date())
    XCTAssertEqual(next.box, 2)
    XCTAssertEqual(next.timesKnown, 0)
  }

  func test_stillLearningFloorsAtZero() {
    var state = SRSState()
    state.box = 0
    let next = SRSAlgorithm.grade(state, as: .stillLearning, now: Date())
    XCTAssertEqual(next.box, 0)
  }

  func test_stillLearningSetsTwoMinutes() {
    let now = Date()
    let state = SRSState()
    let next = SRSAlgorithm.grade(state, as: .stillLearning, now: now)
    XCTAssertEqual(next.dueAt.timeIntervalSince(now), 120, accuracy: 0.001)
  }

  func test_neutralDismissKeepsBoxButReschedules() {
    let now = Date()
    var state = SRSState()
    state.box = 2
    let next = SRSAlgorithm.grade(state, as: .neutralDismiss, now: now)
    XCTAssertEqual(next.box, 2)
    XCTAssertEqual(next.timesKnown, 0)
    XCTAssertEqual(next.dueAt.timeIntervalSince(now), 600, accuracy: 0.001)
  }

  func test_selectsMostOverdue() {
    let now = Date()
    var early = Card(front: "A", back: "1")
    early.srs.dueAt = now.addingTimeInterval(-1000)
    var late = Card(front: "B", back: "2")
    late.srs.dueAt = now.addingTimeInterval(-100)

    let deck = Deck(name: "Test", cards: [late, early])
    let picked = SRSAlgorithm.selectNextCard(decks: [deck], now: now)!
    XCTAssertEqual(picked.card.front, "A")  // the more-overdue one
  }

  func test_picksSoonestWhenNothingDue() {
    let now = Date()
    var future1 = Card(front: "A", back: "1")
    future1.srs.dueAt = now.addingTimeInterval(3600)
    var future2 = Card(front: "B", back: "2")
    future2.srs.dueAt = now.addingTimeInterval(60)

    let deck = Deck(name: "Test", cards: [future1, future2])
    let picked = SRSAlgorithm.selectNextCard(decks: [deck], now: now)!
    XCTAssertEqual(picked.card.front, "B")  // sooner due
  }

  func test_inactiveDecksAreSkipped() {
    let now = Date()
    var card = Card(front: "Hidden", back: "Skip")
    card.srs.dueAt = now.addingTimeInterval(-1000)
    var deck = Deck(name: "Off", cards: [card])
    deck.isActive = false

    let result = SRSAlgorithm.selectNextCard(decks: [deck], now: now)
    XCTAssertNil(result)
  }

  func test_selectNextDueCardReturnsNilWhenNothingDue() {
    let now = Date()
    var future = Card(front: "A", back: "1")
    future.srs.dueAt = now.addingTimeInterval(60)
    let deck = Deck(name: "Test", cards: [future])

    // No soonest-upcoming fallback here — that's what ends a batch run.
    XCTAssertNil(SRSAlgorithm.selectNextDueCard(decks: [deck], now: now))
    XCTAssertNotNil(SRSAlgorithm.selectNextCard(decks: [deck], now: now))
  }

  func test_selectNextDueCardSkipsExcludedCards() {
    let now = Date()
    var first = Card(front: "A", back: "1")
    first.srs.dueAt = now.addingTimeInterval(-1000)
    var second = Card(front: "B", back: "2")
    second.srs.dueAt = now.addingTimeInterval(-100)
    let deck = Deck(name: "Test", cards: [first, second])

    let picked = SRSAlgorithm.selectNextDueCard(
      decks: [deck], excluding: [first.id], now: now)
    XCTAssertEqual(picked?.card.front, "B")

    // Every due card already seen in this run ⇒ the run is over.
    XCTAssertNil(
      SRSAlgorithm.selectNextDueCard(
        decks: [deck], excluding: [first.id, second.id], now: now))
  }

  func test_selectNextDueCardSkipsInactiveDecks() {
    let now = Date()
    var card = Card(front: "Hidden", back: "Skip")
    card.srs.dueAt = now.addingTimeInterval(-1000)
    var deck = Deck(name: "Off", cards: [card])
    deck.isActive = false

    XCTAssertNil(SRSAlgorithm.selectNextDueCard(decks: [deck], now: now))
  }

  func test_dueCountIgnoresFutureAndInactive() {
    let now = Date()
    var dueCard = Card(front: "A", back: "1")
    dueCard.srs.dueAt = now.addingTimeInterval(-10)
    var futureCard = Card(front: "B", back: "2")
    futureCard.srs.dueAt = now.addingTimeInterval(10_000)

    let active = Deck(name: "Active", cards: [dueCard, futureCard])
    var inactive = Deck(name: "Inactive", cards: [dueCard])
    inactive.isActive = false

    XCTAssertEqual(SRSAlgorithm.dueCount(decks: [active, inactive], now: now), 1)
  }
}

final class StudySessionTests: XCTestCase {

  private func dueCard(_ front: String, dueIn seconds: TimeInterval, now: Date) -> Card {
    var card = Card(front: front, back: "\(front)-back")
    card.srs.dueAt = now.addingTimeInterval(seconds)
    return card
  }

  func test_allDecksGathersEveryCard() {
    let now = Date()
    let a = Deck(name: "A", cards: [dueCard("a1", dueIn: -10, now: now)])
    let b = Deck(name: "B", cards: [
      dueCard("b1", dueIn: -5, now: now), dueCard("b2", dueIn: 100, now: now),
    ])
    let queue = StudySession.buildQueue(decks: [a, b], scope: .allDecks)
    XCTAssertEqual(queue.count, 3)
  }

  // Study is deliberate, so inactive decks are still included under "All decks".
  func test_allDecksIncludesInactiveDecks() {
    let now = Date()
    var inactive = Deck(name: "Off", cards: [dueCard("x", dueIn: -10, now: now)])
    inactive.isActive = false
    let queue = StudySession.buildQueue(decks: [inactive], scope: .allDecks)
    XCTAssertEqual(queue.count, 1)
  }

  func test_deckScopeFiltersToThatDeck() {
    let now = Date()
    let a = Deck(name: "A", cards: [dueCard("a1", dueIn: -10, now: now)])
    let b = Deck(name: "B", cards: [dueCard("b1", dueIn: -5, now: now)])
    let queue = StudySession.buildQueue(decks: [a, b], scope: .deck(b.id))
    XCTAssertEqual(queue.count, 1)
    XCTAssertEqual(queue.first?.deckId, b.id)
  }

  func test_orderedMostOverdueFirstThenSoonest() {
    let now = Date()
    // Built in deliberately wrong order to prove sorting happens.
    let deck = Deck(name: "D", cards: [
      dueCard("upcoming-late", dueIn: 3600, now: now),
      dueCard("most-overdue", dueIn: -1000, now: now),
      dueCard("upcoming-soon", dueIn: 60, now: now),
      dueCard("less-overdue", dueIn: -100, now: now),
    ])
    let fronts = StudySession.buildQueue(decks: [deck], scope: .allDecks)
      .compactMap { item in
        deck.cards.first { $0.id == item.cardId }?.front
      }
    XCTAssertEqual(
      fronts, ["most-overdue", "less-overdue", "upcoming-soon", "upcoming-late"])
  }

  func test_promptSideResolvesFrontAndBack() {
    let now = Date()
    var frontDeck = Deck(name: "F", cards: [dueCard("f", dueIn: 0, now: now)])
    frontDeck.promptSide = .front
    var backDeck = Deck(name: "B", cards: [dueCard("b", dueIn: 0, now: now)])
    backDeck.promptSide = .back

    XCTAssertEqual(
      StudySession.buildQueue(decks: [frontDeck], scope: .allDecks).first?.promptIsFront,
      true)
    XCTAssertEqual(
      StudySession.buildQueue(decks: [backDeck], scope: .allDecks).first?.promptIsFront,
      false)
  }

  func test_emptyAndMissingScopesYieldEmptyQueue() {
    XCTAssertTrue(StudySession.buildQueue(decks: [], scope: .allDecks).isEmpty)
    let deck = Deck(name: "D", cards: [Card(front: "a", back: "b")])
    XCTAssertTrue(
      StudySession.buildQueue(decks: [deck], scope: .deck(UUID())).isEmpty)
  }
}

final class AppSettingsTests: XCTestCase {

  private func makeSettings(
    start: (h: Int, m: Int),
    end: (h: Int, m: Int)
  ) -> AppSettings {
    var s = AppSettings()
    s.quietHoursEnabled = true
    let cal = Calendar.current
    s.quietHoursStart = cal.date(
      bySettingHour: start.h, minute: start.m, second: 0, of: Date())!
    s.quietHoursEnd = cal.date(
      bySettingHour: end.h, minute: end.m, second: 0, of: Date())!
    return s
  }

  private func time(_ h: Int, _ m: Int) -> Date {
    Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: Date())!
  }

  func test_sameDayWindow() {
    let s = makeSettings(start: (13, 0), end: (15, 0))
    XCTAssertTrue(s.isQuietHour(at: time(14, 0)))
    XCTAssertFalse(s.isQuietHour(at: time(12, 59)))
    XCTAssertFalse(s.isQuietHour(at: time(15, 0)))  // half-open: end excluded
    XCTAssertTrue(s.isQuietHour(at: time(13, 0)))  // start included
  }

  func test_crossesMidnight() {
    let s = makeSettings(start: (22, 0), end: (8, 0))
    XCTAssertTrue(s.isQuietHour(at: time(23, 0)))
    XCTAssertTrue(s.isQuietHour(at: time(1, 30)))
    XCTAssertTrue(s.isQuietHour(at: time(22, 0)))
    XCTAssertFalse(s.isQuietHour(at: time(8, 0)))
    XCTAssertFalse(s.isQuietHour(at: time(12, 0)))
  }

  func test_disabledIsNeverQuiet() {
    var s = makeSettings(start: (22, 0), end: (8, 0))
    s.quietHoursEnabled = false
    XCTAssertFalse(s.isQuietHour(at: time(23, 0)))
  }

  func test_zeroLengthWindowIsNeverQuiet() {
    let s = makeSettings(start: (9, 0), end: (9, 0))
    XCTAssertFalse(s.isQuietHour(at: time(9, 0)))
  }

  func test_defaultsAreSane() {
    let s = AppSettings()
    XCTAssertEqual(s.intervalMinutes, 20)
    XCTAssertEqual(s.popupCorner, .topRight)
    XCTAssertFalse(s.quietHoursEnabled)
    XCTAssertFalse(s.launchAtLogin)
    XCTAssertEqual(s.batchSize, 1)  // behaves exactly like the pre-batch app
    XCTAssertEqual(s.cardsPerRun, 1)
  }

  func test_cardsPerRunClampsGarbage() {
    var s = AppSettings()
    s.batchSize = 0
    XCTAssertEqual(s.cardsPerRun, 1)
    s.batchSize = -3
    XCTAssertEqual(s.cardsPerRun, 1)
    s.batchSize = 5
    XCTAssertEqual(s.cardsPerRun, 5)
    s.batchSize = 9_999
    XCTAssertEqual(s.cardsPerRun, AppSettings.maxBatchSize)
  }

  func test_codableRoundTrip() throws {
    var s = AppSettings()
    s.intervalMinutes = 42
    s.popupCorner = .bottomLeft
    s.quietHoursEnabled = true
    s.batchSize = 4
    let data = try JSONEncoder().encode(s)
    let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
    XCTAssertEqual(decoded, s)
  }

  // Settings saved before batchSize existed must still load, with batching off.
  func test_decodesLegacySettingsWithoutBatchSize() throws {
    let json = """
      {
        "intervalMinutes": 45,
        "quietHoursStart": 0,
        "quietHoursEnd": 0,
        "quietHoursEnabled": false,
        "popupCorner": "bottomLeft",
        "launchAtLogin": true
      }
      """
    let s = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
    XCTAssertEqual(s.intervalMinutes, 45)
    XCTAssertEqual(s.popupCorner, .bottomLeft)
    XCTAssertTrue(s.launchAtLogin)
    XCTAssertEqual(s.batchSize, 1)
  }
}

final class DeckCodableTests: XCTestCase {

  private func decoder() -> JSONDecoder {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .iso8601
    return d
  }

  // A deck saved before promptSide existed must still load (default .front),
  // not throw — otherwise users would lose all their decks on upgrade.
  func test_decodesLegacyDeckWithoutPromptSide() throws {
    let json = """
      {
        "id": "11111111-1111-1111-1111-111111111111",
        "name": "Legacy",
        "cards": [],
        "isActive": true,
        "createdAt": "2020-01-01T00:00:00Z"
      }
      """
    let deck = try decoder().decode(Deck.self, from: Data(json.utf8))
    XCTAssertEqual(deck.name, "Legacy")
    XCTAssertEqual(deck.promptSide, .front)
  }

  func test_promptSideRoundTrips() throws {
    var deck = Deck(name: "Verbs", cards: [Card(front: "être", back: "to be")])
    deck.promptSide = .back
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(deck)
    let decoded = try decoder().decode(Deck.self, from: data)
    // Note: don't compare full equality — .iso8601 drops sub-second precision
    // on createdAt. Assert the fields that matter.
    XCTAssertEqual(decoded.promptSide, .back)
    XCTAssertEqual(decoded.id, deck.id)
    XCTAssertEqual(decoded.name, "Verbs")
    XCTAssertEqual(decoded.cards.first?.back, "to be")
  }
}

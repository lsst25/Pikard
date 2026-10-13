import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {

  @Published private(set) var decks: [Deck] = []
  @Published var settings: AppSettings = AppSettings()
  @Published var lastError: String? = nil

  private let store: Store<[Deck]>
  private let settingsStore: Store<AppSettings>
  private var settingsSink: AnyCancellable?

  // Coalesces high-frequency edits (typing in the deck editor) into one disk write.
  private let saveTrigger = PassthroughSubject<Void, Never>()
  private var saveSink: AnyCancellable?

  init() {
    // Construct both stores first so the stored properties are initialised on
    // every path; surface load failures via `lastError` rather than crashing.
    let decksStore = (try? Store<[Deck]>(filename: "decks.json"))
    let settingsStore = (try? Store<AppSettings>(filename: "settings.json"))

    // If a store can't even be constructed, the app can't persist — fail loudly
    // in development, but keep an in-memory fallback path.
    self.store = decksStore ?? Store<[Deck]>.inMemory(filename: "decks.json")
    self.settingsStore =
      settingsStore ?? Store<AppSettings>.inMemory(filename: "settings.json")

    do {
      decks = (try store.load()) ?? []
    } catch {
      lastError = "Failed to load decks: \(error)"
    }

    do {
      settings = (try self.settingsStore.load()) ?? AppSettings()
    } catch {
      lastError = "Failed to load settings: \(error)"
    }

    // Persist settings whenever they change, coalescing rapid edits (slider drag).
    settingsSink =
      $settings
      .dropFirst()  // skip the value we just loaded
      .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
      .sink { [weak self] newValue in
        do { try self?.settingsStore.save(newValue) } catch {
          self?.lastError = "Settings save failed: \(error)"
        }
      }

    // Debounced deck persistence for text edits.
    saveSink =
      saveTrigger
      .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
      .sink { [weak self] in self?.persist() }
  }

  func importDeck(named name: String, fromQuizletText text: String) -> Int {
    let cards = QuizletParser.parse(text)

    if let idx = decks.firstIndex(where: { $0.name == name }) {
      let merged = QuizletParser.merge(existing: decks[idx].cards, incoming: cards)
      decks[idx].cards = merged
    } else {
      decks.append(Deck(name: name, cards: cards))
    }

    persist()
    return cards.count
  }

  func addDeck(_ deck: Deck) {
    decks.append(deck)
    persist()
  }

  func updateCard(_ card: Card, inDeckId deckId: UUID) {
    guard let deckIdx = decks.firstIndex(where: { $0.id == deckId }) else { return }
    guard let cardIdx = decks[deckIdx].cards.firstIndex(where: { $0.id == card.id })
    else { return }
    decks[deckIdx].cards[cardIdx] = card
    persist()
  }

  func toggleActive(deckId: UUID) {
    guard let idx = decks.firstIndex(where: { $0.id == deckId }) else { return }
    decks[idx].isActive.toggle()
    persist()
  }

  func setDeckActive(id: UUID, to active: Bool) {
    guard let idx = decks.firstIndex(where: { $0.id == id }) else { return }
    guard decks[idx].isActive != active else { return }
    decks[idx].isActive = active
    persist()
  }

  func setDeckPromptSide(id: UUID, to side: Deck.PromptSide) {
    guard let idx = decks.firstIndex(where: { $0.id == id }) else { return }
    guard decks[idx].promptSide != side else { return }
    decks[idx].promptSide = side
    persist()
  }

  /// Force any debounced edits to disk immediately. Call before window close /
  /// app termination so in-flight text edits aren't lost.
  func flush() {
    persist()
    do { try settingsStore.save(settings) } catch {
      lastError = "Settings save failed: \(error)"
    }
  }

  func grade(card: Card, in deckId: UUID, as grade: Grade) {
    guard let deckIdx = decks.firstIndex(where: { $0.id == deckId }) else { return }
    guard let cardIdx = decks[deckIdx].cards.firstIndex(where: { $0.id == card.id })
    else { return }
    var updated = decks[deckIdx].cards[cardIdx]
    updated.srs = SRSAlgorithm.grade(
      updated.srs, as: grade, intervals: settings.effectiveBoxIntervals)
    decks[deckIdx].cards[cardIdx] = updated
    persist()
  }

  // MARK: Deck management

  /// Create an empty deck and return its id (caller can select it).
  @discardableResult
  func createDeck(named name: String = "New Deck") -> UUID {
    let deck = Deck(name: name, cards: [])
    decks.append(deck)
    persist()
    return deck.id
  }

  func deleteDeck(id: UUID) {
    decks.removeAll { $0.id == id }
    persist()
  }

  /// Rename a deck. Text-rate edits are debounced to disk.
  func setDeckName(id: UUID, to name: String) {
    guard let idx = decks.firstIndex(where: { $0.id == id }) else { return }
    guard decks[idx].name != name else { return }
    decks[idx].name = name
    saveTrigger.send()
  }

  // MARK: Card management

  @discardableResult
  func addCard(front: String = "", back: String = "", to deckId: UUID) -> UUID? {
    guard let idx = decks.firstIndex(where: { $0.id == deckId }) else { return nil }
    let card = Card(front: front, back: back)
    decks[idx].cards.append(card)
    persist()
    return card.id
  }

  func deleteCard(id: UUID, in deckId: UUID) {
    guard let idx = decks.firstIndex(where: { $0.id == deckId }) else { return }
    decks[idx].cards.removeAll { $0.id == id }
    persist()
  }

  /// Update a card's text, preserving its SRS state. Debounced to disk.
  func setCardText(cardId: UUID, in deckId: UUID, front: String, back: String) {
    guard let di = decks.firstIndex(where: { $0.id == deckId }),
      let ci = decks[di].cards.firstIndex(where: { $0.id == cardId })
    else { return }
    guard decks[di].cards[ci].front != front || decks[di].cards[ci].back != back
    else { return }
    decks[di].cards[ci].front = front
    decks[di].cards[ci].back = back
    saveTrigger.send()
  }

  private func persist() {
    do {
      try store.save(decks)
    } catch {
      lastError = "Save failed: \(error)"
    }
  }
}

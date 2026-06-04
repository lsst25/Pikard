import Foundation

struct Deck: Codable, Identifiable, Equatable {
  let id: UUID
  var name: String
  var cards: [Card]
  var isActive: Bool
  var createdAt: Date
  /// Which face shows first when a card from this deck pops up.
  var promptSide: PromptSide

  enum PromptSide: String, Codable, CaseIterable, Identifiable {
    case front, back, random
    var id: String { rawValue }
    var displayName: String {
      switch self {
      case .front: return "Front first"
      case .back: return "Back first"
      case .random: return "Random"
      }
    }
  }

  init(name: String, cards: [Card], promptSide: PromptSide = .front) {
    self.id = UUID()
    self.name = name
    self.cards = cards
    self.isActive = true
    self.createdAt = Date()
    self.promptSide = promptSide
  }

  enum CodingKeys: String, CodingKey {
    case id, name, cards, isActive, createdAt, promptSide
  }

  // Custom decode so decks saved before `promptSide` existed still load.
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(UUID.self, forKey: .id)
    name = try c.decode(String.self, forKey: .name)
    cards = try c.decode([Card].self, forKey: .cards)
    isActive = try c.decode(Bool.self, forKey: .isActive)
    createdAt = try c.decode(Date.self, forKey: .createdAt)
    promptSide = try c.decodeIfPresent(PromptSide.self, forKey: .promptSide) ?? .front
  }
}

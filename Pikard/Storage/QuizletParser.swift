import Foundation

enum QuizletParser {
  static func parse(_ text: String) -> [Card] {
    let normalised = normaliseLineEndings(text)
    let separator = detectFieldSeparator(in: normalised)
    let rows = splitIntoRows(normalised)

    return rows.compactMap { line in
      cardFrom(line: line, separator: separator)
    }
  }

  private static func normaliseLineEndings(_ text: String) -> String {
    text
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
  }

  private static func detectFieldSeparator(in text: String) -> Character {
    if text.contains("\t") { return "\t" }
    if text.contains(",") { return "," }
    if text.contains(";") { return ";" }

    return "\t"
  }

  private static func splitIntoRows(_ text: String) -> [String] {
    text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
  }

  private static func cardFrom(line: String, separator: Character) -> Card? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return nil }

    let parts =
      trimmed
      .split(separator: separator, omittingEmptySubsequences: false)
      .map { $0.trimmingCharacters(in: .whitespaces) }

    guard parts.count >= 2,
      !parts[0].isEmpty,
      !parts[1].isEmpty
    else {
      return nil
    }

    let front = parts[0]
    let back: String

    if parts.count == 2 {
      back = parts[1]
    } else {
      back = parts.dropFirst().joined(separator: " — ")
    }

    return Card(front: front, back: back)
  }

  static func merge(existing: [Card], incoming: [Card]) -> [Card] {
    var seen = Set<String>(existing.map { Self.key(for: $0) })
    var merged = existing
    for card in incoming {
      let k = Self.key(for: card)
      if !seen.contains(k) {
        merged.append(card)
        seen.insert(k)
      }
    }

    return merged
  }

  private static func key(for card: Card) -> String {
    "\(card.front.lowercased())|\(card.back.lowercased())"
  }
}

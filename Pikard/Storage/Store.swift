import Foundation

enum StoreError: Error {
  case noApplicationSupport
  case decode(String)
}

final class Store<T: Codable> {

  private let url: URL
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  /// Primary initialiser: persists under `~/Library/Application Support/Pikard/`.
  convenience init(filename: String) throws {
    guard
      let support = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
      ).first
    else {
      throw StoreError.noApplicationSupport
    }
    let dir = support.appendingPathComponent("Pikard", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    self.init(directory: dir, filename: filename)
  }

  private init(directory: URL, filename: String) {
    self.url = directory.appendingPathComponent(filename)

    let e = JSONEncoder()
    e.outputFormatting = [.prettyPrinted, .sortedKeys]
    e.dateEncodingStrategy = .iso8601
    self.encoder = e

    let d = JSONDecoder()
    d.dateDecodingStrategy = .iso8601
    self.decoder = d
  }

  /// Non-throwing fallback used when Application Support is unavailable.
  /// Persists to the temporary directory so the app stays usable for the session.
  static func inMemory(filename: String) -> Store<T> {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("Pikard", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return Store(directory: dir, filename: filename)
  }

  func load() throws -> T? {
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    let data = try Data(contentsOf: url)
    do {
      return try decoder.decode(T.self, from: data)
    } catch {
      throw StoreError.decode(String(describing: error))
    }
  }

  func save(_ value: T) throws {
    let data = try encoder.encode(value)
    try data.write(to: url, options: [.atomic])
  }
}

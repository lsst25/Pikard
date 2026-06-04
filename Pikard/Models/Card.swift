import Foundation

struct Card: Codable, Identifiable, Equatable {
  let id: UUID
  var front: String
  var back: String
  var srs: SRSState

  init(front: String, back: String) {
    self.id = UUID()
    self.front = front
    self.back = back
    self.srs = SRSState()
  }
}

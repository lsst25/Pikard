import Foundation

struct SRSState: Codable, Equatable {
  var box: Int = 0
  var dueAt: Date = Date()
  var lastGradedAt: Date? = nil
  var timesSeen: Int = 0
  var timesKnown: Int = 0
}

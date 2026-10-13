import SwiftUI

/// Colour for a card's Leitner box dot, from red (box 0, not yet learned) through
/// yellow to green (last box, learned). Scales to however many boxes the user
/// has configured, so the ramp always spans the whole ladder.
enum BoxColor {

  static func color(box: Int, boxCount: Int) -> Color {
    let last = max(0, boxCount - 1)
    let clamped = min(last, max(0, box))
    // Hue 0 = red, 1/3 = green. A single-box ladder is "learned" throughout.
    let fraction = last == 0 ? 1.0 : Double(clamped) / Double(last)
    return Color(hue: fraction / 3, saturation: 0.75, brightness: 0.85)
  }

  /// Tooltip text for a box dot, showing the box as 1-based out of the total.
  static func label(box: Int, boxCount: Int) -> String {
    let clamped = min(max(0, boxCount - 1), max(0, box))
    return "Leitner box \(clamped + 1) of \(boxCount)"
  }
}

import Foundation

struct AppSettings: Codable, Equatable {

  /// Minutes between popups. Spec default: 20.
  var intervalMinutes: Double = 20

  /// Start of the quiet window (time-of-day; the date part is ignored).
  var quietHoursStart: Date = AppSettings.defaultTime(hour: 22)

  /// End of the quiet window.
  var quietHoursEnd: Date = AppSettings.defaultTime(hour: 8)

  /// Whether quiet hours are enabled at all.
  var quietHoursEnabled: Bool = false

  /// Which corner the popup appears in.
  var popupCorner: PopupCorner = .topRight

  /// Whether the app registers itself to launch at login.
  var launchAtLogin: Bool = false

  enum PopupCorner: String, Codable, CaseIterable, Identifiable {
    case topLeft, topRight, bottomLeft, bottomRight
    var id: String { rawValue }
    var displayName: String {
      switch self {
      case .topLeft: return "Top-left"
      case .topRight: return "Top-right"
      case .bottomLeft: return "Bottom-left"
      case .bottomRight: return "Bottom-right"
      }
    }
  }

  private static func defaultTime(hour: Int) -> Date {
    Calendar.current.date(
      bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
  }
}

extension AppSettings {

  /// True if `now`'s time-of-day falls within [start, end), where the window
  /// may cross midnight. Returns false when quiet hours are disabled.
  func isQuietHour(at now: Date, calendar: Calendar = .current) -> Bool {
    guard quietHoursEnabled else { return false }
    let nMin = Self.minutesOfDay(now, calendar: calendar)
    let sMin = Self.minutesOfDay(quietHoursStart, calendar: calendar)
    let eMin = Self.minutesOfDay(quietHoursEnd, calendar: calendar)

    if sMin == eMin { return false }  // zero-length window
    if sMin < eMin { return nMin >= sMin && nMin < eMin }  // same-day window
    return nMin >= sMin || nMin < eMin  // crosses midnight, e.g. 22:00 → 08:00
  }

  /// Seconds from `now` until the next occurrence of `quietHoursEnd`'s time-of-day.
  func secondsUntilQuietEnds(now: Date, calendar: Calendar = .current) -> TimeInterval
  {
    let parts = calendar.dateComponents([.hour, .minute], from: quietHoursEnd)
    guard
      let next = calendar.nextDate(
        after: now, matching: parts, matchingPolicy: .nextTime)
    else {
      return 3600  // safe fallback
    }
    return next.timeIntervalSince(now)
  }

  private static func minutesOfDay(_ date: Date, calendar: Calendar) -> Int {
    let parts = calendar.dateComponents([.hour, .minute], from: date)
    return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
  }
}

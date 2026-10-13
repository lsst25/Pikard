import Foundation

struct AppSettings: Codable, Equatable {

  /// Minutes between popups. Spec default: 20.
  var intervalMinutes: Double = 20

  /// How many cards one popup run walks through back-to-back. 1 = the classic
  /// single-card popup. Higher values let you use a longer interval and then
  /// clear a short batch in one sitting: each Known / Still-learning grade
  /// swaps in the next due card instead of closing the popup.
  var batchSize: Int = 1

  /// Start of the quiet window (time-of-day; the date part is ignored).
  var quietHoursStart: Date = AppSettings.defaultTime(hour: 22)

  /// End of the quiet window.
  var quietHoursEnd: Date = AppSettings.defaultTime(hour: 8)

  /// Whether quiet hours are enabled at all.
  var quietHoursEnabled: Bool = false

  /// Which corner the popup appears in.
  var popupCorner: PopupCorner = .topRight

  /// Whether clicking outside the popup dismisses it. Off by default so a card
  /// stays put until you grade or dismiss it, rather than vanishing the moment
  /// you click back into your work.
  var dismissOnOutsideClick: Bool = false

  /// Whether the app registers itself to launch at login.
  var launchAtLogin: Bool = false

  /// Review interval for each Leitner box, in seconds. A card graded Known moves
  /// up one box and comes back after that box's interval; the last box is where
  /// learned cards settle, so its interval is the longest gap a card ever gets.
  /// Between 1 and `maxBoxes` entries — see `effectiveBoxIntervals` for the sanitized view.
  var boxIntervals: [TimeInterval] = AppSettings.defaultBoxIntervals

  /// When nothing is due, whether a popup still shows the soonest-upcoming card
  /// (the original behaviour) or stays silent until a card is actually due.
  var showUpcomingWhenNothingDue: Bool = true

  init() {}

  // Migration-safe decode: back-fill any key missing from older settings.json
  // (a synthesized decoder would throw on the first absent key and reset every
  // setting to its default). See `Deck.init(from:)` for the same pattern.
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let d = AppSettings()
    intervalMinutes =
      try c.decodeIfPresent(Double.self, forKey: .intervalMinutes) ?? d.intervalMinutes
    batchSize =
      try c.decodeIfPresent(Int.self, forKey: .batchSize) ?? d.batchSize
    quietHoursStart =
      try c.decodeIfPresent(Date.self, forKey: .quietHoursStart) ?? d.quietHoursStart
    quietHoursEnd =
      try c.decodeIfPresent(Date.self, forKey: .quietHoursEnd) ?? d.quietHoursEnd
    quietHoursEnabled =
      try c.decodeIfPresent(Bool.self, forKey: .quietHoursEnabled) ?? d.quietHoursEnabled
    popupCorner =
      try c.decodeIfPresent(PopupCorner.self, forKey: .popupCorner) ?? d.popupCorner
    dismissOnOutsideClick =
      try c.decodeIfPresent(Bool.self, forKey: .dismissOnOutsideClick)
      ?? d.dismissOnOutsideClick
    launchAtLogin =
      try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? d.launchAtLogin
    boxIntervals =
      try c.decodeIfPresent([TimeInterval].self, forKey: .boxIntervals) ?? d.boxIntervals
    showUpcomingWhenNothingDue =
      try c.decodeIfPresent(Bool.self, forKey: .showUpcomingWhenNothingDue)
      ?? d.showUpcomingWhenNothingDue
  }

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

  /// Upper bound on `batchSize`, shared by the settings UI and the scheduler.
  static let maxBatchSize = 20

  /// `batchSize` clamped to a usable range — persisted JSON can hold anything.
  var cardsPerRun: Int { min(Self.maxBatchSize, max(1, batchSize)) }

  /// The Leitner ladder the app shipped with: 5 min → 7 days over six boxes.
  static let defaultBoxIntervals: [TimeInterval] = [
    5 * 60,
    30 * 60,
    4 * 3600,
    24 * 3600,
    3 * 24 * 3600,
    7 * 24 * 3600,
  ]

  /// Upper bound on the number of boxes, shared by the settings UI and the SRS.
  static let maxBoxes = 25

  /// Shortest interval a box may have (one minute).
  static let minBoxInterval: TimeInterval = 60

  /// `boxIntervals` made safe to schedule with: never empty, at most `maxBoxes`
  /// entries, every entry at least `minBoxInterval`, and no non-finite values —
  /// persisted JSON can hold anything.
  var effectiveBoxIntervals: [TimeInterval] {
    let cleaned = boxIntervals
      .prefix(Self.maxBoxes)
      .map { $0.isFinite ? max(Self.minBoxInterval, $0) : Self.minBoxInterval }
    return cleaned.isEmpty ? Self.defaultBoxIntervals : Array(cleaned)
  }

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

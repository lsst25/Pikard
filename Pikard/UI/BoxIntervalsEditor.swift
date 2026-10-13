import SwiftUI

/// Edits the Leitner ladder: one row per box with a number + unit, plus
/// add / remove / reset. Rows carry their own identity so removing one in the
/// middle doesn't shuffle text-field state between neighbours; the binding is
/// kept in sync whenever a row changes, and rows are rebuilt only when the
/// binding changes underneath them (e.g. "Reset to defaults").
struct BoxIntervalsEditor: View {

  @Binding var intervals: [TimeInterval]

  @State private var rows: [Row] = []

  enum Unit: String, CaseIterable, Identifiable {
    case minutes, hours, days

    var id: String { rawValue }

    var seconds: TimeInterval {
      switch self {
      case .minutes: return 60
      case .hours: return 3600
      case .days: return 86_400
      }
    }

    var displayName: String {
      switch self {
      case .minutes: return "min"
      case .hours: return "hours"
      case .days: return "days"
      }
    }
  }

  struct Row: Identifiable, Equatable {
    let id: UUID
    var value: Double
    var unit: Unit

    var seconds: TimeInterval { value * unit.seconds }

    /// Pick the largest unit that divides the interval evenly, so 7 days reads
    /// as "7 days" rather than "10080 min".
    init(seconds: TimeInterval) {
      id = UUID()
      let whole = seconds.rounded()
      if whole >= Unit.days.seconds, whole.truncatingRemainder(dividingBy: Unit.days.seconds) == 0 {
        unit = .days
      } else if whole >= Unit.hours.seconds,
        whole.truncatingRemainder(dividingBy: Unit.hours.seconds) == 0
      {
        unit = .hours
      } else {
        unit = .minutes
      }
      value = seconds / unit.seconds
    }

    /// Keep the row inside what the scheduler accepts (at least one minute).
    mutating func sanitize() {
      let floor = AppSettings.minBoxInterval / unit.seconds
      if !value.isFinite || value < floor { value = floor }
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      ForEach($rows) { $row in
        rowView($row)
      }

      HStack {
        Button {
          addBox()
        } label: {
          Label("Add box", systemImage: "plus")
        }
        .disabled(rows.count >= AppSettings.maxBoxes)

        Spacer()

        Button("Reset to defaults") {
          intervals = AppSettings.defaultBoxIntervals
        }
        .disabled(intervals == AppSettings.defaultBoxIntervals)
      }
      .padding(.top, 4)
    }
    .onAppear { rows = Self.makeRows(intervals) }
    .onChange(of: intervals) { _, new in
      // Only rebuild when the change didn't originate from these rows.
      if rows.map(\.seconds) != new { rows = Self.makeRows(new) }
    }
    .onChange(of: rows) { _, new in
      var cleaned = new
      for i in cleaned.indices { cleaned[i].sanitize() }
      if cleaned != new {
        rows = cleaned  // re-enters once with a stable value
        return
      }
      let seconds = cleaned.map(\.seconds)
      if seconds != intervals { intervals = seconds }
    }
  }

  private func rowView(_ row: Binding<Row>) -> some View {
    let index = rows.firstIndex { $0.id == row.wrappedValue.id } ?? 0
    return HStack(spacing: 8) {
      Text("Box \(index + 1)")
        .frame(width: 52, alignment: .leading)
        .monospacedDigit()

      TextField("", value: row.value, format: .number.precision(.fractionLength(0...2)))
        .textFieldStyle(.roundedBorder)
        .multilineTextAlignment(.trailing)
        .frame(width: 68)

      Picker("", selection: row.unit) {
        ForEach(Unit.allCases) { unit in
          Text(unit.displayName).tag(unit)
        }
      }
      .labelsHidden()
      .pickerStyle(.menu)
      .frame(width: 90)

      Spacer()

      Button {
        rows.removeAll { $0.id == row.wrappedValue.id }
      } label: {
        Image(systemName: "minus.circle")
      }
      .buttonStyle(.borderless)
      .disabled(rows.count <= 1)
      .help(rows.count <= 1 ? "At least one box is required" : "Remove this box")
    }
  }

  /// A new box doubles the gap of the last one, so the ladder keeps climbing.
  private func addBox() {
    guard rows.count < AppSettings.maxBoxes else { return }
    let last = rows.last?.seconds ?? AppSettings.minBoxInterval
    rows.append(Row(seconds: last * 2))
  }

  private static func makeRows(_ intervals: [TimeInterval]) -> [Row] {
    let safe = intervals.isEmpty ? AppSettings.defaultBoxIntervals : intervals
    return safe.prefix(AppSettings.maxBoxes).map { Row(seconds: $0) }
  }
}

#Preview {
  @Previewable @State var intervals = AppSettings.defaultBoxIntervals
  Form {
    Section("Learning intervals") {
      BoxIntervalsEditor(intervals: $intervals)
    }
  }
  .formStyle(.grouped)
  .frame(width: 420, height: 400)
}

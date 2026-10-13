import SwiftUI

struct SettingsView: View {

  @ObservedObject var appState: AppState

  var body: some View {
    Form {
      Section("Schedule") {
        intervalRow
        batchRow
      }

      Section("Learning intervals") {
        BoxIntervalsEditor(intervals: $appState.settings.boxIntervals)
        Text(
          "Known moves a card up one box and brings it back after that box's "
            + "interval; Still learning moves it down one. The last box is where "
            + "learned cards settle. Up to \(AppSettings.maxBoxes) boxes."
        )
        .font(.caption)
        .foregroundStyle(.secondary)

        Toggle(
          "Show an upcoming card when nothing is due",
          isOn: $appState.settings.showUpcomingWhenNothingDue)
        Text(
          appState.settings.showUpcomingWhenNothingDue
            ? "A popup always shows something, even a card that isn't due yet."
            : "Popups stay quiet until a card is actually due."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      Section("Quiet hours") {
        Toggle("Enable quiet hours", isOn: $appState.settings.quietHoursEnabled)
        if appState.settings.quietHoursEnabled {
          DatePicker(
            "From",
            selection: $appState.settings.quietHoursStart,
            displayedComponents: .hourAndMinute)
          DatePicker(
            "Until",
            selection: $appState.settings.quietHoursEnd,
            displayedComponents: .hourAndMinute)
        }
      }

      Section("Popup") {
        Picker("Corner", selection: $appState.settings.popupCorner) {
          ForEach(AppSettings.PopupCorner.allCases) { corner in
            Text(corner.displayName).tag(corner)
          }
        }
        .pickerStyle(.menu)

        Toggle(
          "Dismiss when I click outside",
          isOn: $appState.settings.dismissOnOutsideClick)
        Text("Off: a card stays until you grade or dismiss it.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section("Startup") {
        Toggle("Launch Pikard at login", isOn: $appState.settings.launchAtLogin)
      }
    }
    .formStyle(.grouped)
    .frame(width: 440, height: 640)
  }

  private var intervalRow: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text("Interval")
        Spacer()
        Text("\(Int(appState.settings.intervalMinutes)) min")
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }
      Slider(value: $appState.settings.intervalMinutes, in: 5...120, step: 5)
    }
  }

  private var batchRow: some View {
    VStack(alignment: .leading, spacing: 4) {
      Stepper(
        value: $appState.settings.batchSize,
        in: 1...AppSettings.maxBatchSize
      ) {
        HStack {
          Text("Cards per popup")
          Spacer()
          Text("\(appState.settings.batchSize)")
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
      }
      Text(
        appState.settings.batchSize > 1
          ? "Grading a card brings up the next one; dismissing with ✕ ends the batch."
          : "One card per popup."
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    }
  }
}

#Preview {
  SettingsView(appState: AppState())
}

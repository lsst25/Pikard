import SwiftUI

struct SettingsView: View {

  @ObservedObject var appState: AppState

  var body: some View {
    Form {
      Section("Schedule") {
        intervalRow
        batchRow
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
    .frame(width: 420, height: 440)
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

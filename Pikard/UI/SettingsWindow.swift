import SwiftUI

struct SettingsView: View {

  @ObservedObject var appState: AppState

  var body: some View {
    Form {
      Section("Schedule") {
        intervalRow
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
      }

      Section("Startup") {
        Toggle("Launch Pikard at login", isOn: $appState.settings.launchAtLogin)
      }
    }
    .formStyle(.grouped)
    .frame(width: 420, height: 380)
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
      Slider(value: $appState.settings.intervalMinutes, in: 5...120, step: 1)
    }
  }
}

#Preview {
  SettingsView(appState: AppState())
}

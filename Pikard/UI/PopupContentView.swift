// UI/PopupContentView.swift
import SwiftUI

struct PopupContentView: View {
  let onDismiss: () -> Void

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(.background)
        .shadow(radius: 0)  // shadow is on the NSPanel itself

      VStack(spacing: 16) {
        Text("Hello, Pikard.")
          .font(.title2)
          .foregroundStyle(.primary)
        Text("Click to dismiss.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
    }
    .contentShape(Rectangle())
    .onTapGesture { onDismiss() }
    .frame(width: 360, height: 220)
  }
}

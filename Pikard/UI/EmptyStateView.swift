import SwiftUI

struct EmptyStateView: View {
  let message: String
  let onDismiss: () -> Void

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(.background)
        .overlay(
          RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )

      VStack(spacing: 8) {
        Image(systemName: "checkmark.circle")
          .font(.system(size: 36))
          .foregroundStyle(.green)
        Text(message)
          .font(.body)
          .multilineTextAlignment(.center)
          .foregroundStyle(.secondary)
          .padding(.horizontal, 20)
      }
    }
    .frame(width: 360, height: 140)
    .contentShape(Rectangle())
    .onTapGesture { onDismiss() }
  }
}

#Preview {
  EmptyStateView(message: "All caught up — next card in 12 min.", onDismiss: {})
}

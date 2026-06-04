import SwiftUI

struct CardView: View {

  let card: Card
  let onGrade: (Grade) -> Void
  let onDismiss: () -> Void

  /// Whether the prompt (question) face is the card's front. `.random` is
  /// resolved once per popup, in init.
  private let promptIsFront: Bool

  @State private var showingAnswer = false

  init(
    card: Card,
    promptSide: Deck.PromptSide = .front,
    onGrade: @escaping (Grade) -> Void,
    onDismiss: @escaping () -> Void
  ) {
    self.card = card
    self.onGrade = onGrade
    self.onDismiss = onDismiss
    switch promptSide {
    case .front: promptIsFront = true
    case .back: promptIsFront = false
    case .random: promptIsFront = Bool.random()
    }
  }

  private var promptText: String { promptIsFront ? card.front : card.back }
  private var answerText: String { promptIsFront ? card.back : card.front }

  var body: some View {
    ZStack {
      background

      ZStack {
        promptFace
          .opacity(showingAnswer ? 0 : 1)
          .rotation3DEffect(
            .degrees(showingAnswer ? 180 : 0),
            axis: (x: 0, y: 1, z: 0),
            perspective: 0.6)

        answerFace
          .opacity(showingAnswer ? 1 : 0)
          .rotation3DEffect(
            .degrees(showingAnswer ? 0 : -180),
            axis: (x: 0, y: 1, z: 0),
            perspective: 0.6)
      }

      boxDot
      dismissButton
      keyboardShortcuts
    }
    .onChange(of: card.id) { _, _ in
      showingAnswer = false
    }
    .frame(width: 360, height: 220)
    .contentShape(Rectangle())
    .onTapGesture { flip() }
  }

  // MARK: Faces

  private var promptFace: some View {
    VStack(spacing: 14) {
      Spacer()
      Text(promptText)
        .font(.title)
        .multilineTextAlignment(.center)
        .lineLimit(4)
        .minimumScaleFactor(0.6)
      Text("Click or press Space to flip")
        .font(.caption)
        .foregroundStyle(.tertiary)
      Spacer()
    }
    .padding(.horizontal, 24)
  }

  private var answerFace: some View {
    VStack(spacing: 14) {
      Spacer()
      Text(answerText)
        .font(.title2)
        .multilineTextAlignment(.center)
        .lineLimit(4)
        .minimumScaleFactor(0.6)
      gradeButtons
      Spacer()
    }
    .padding(.horizontal, 24)
  }

  private var background: some View {
    RoundedRectangle(cornerRadius: 14, style: .continuous)
      .fill(.background)
      .overlay(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .stroke(Color.primary.opacity(0.06), lineWidth: 1)
      )
  }

  // MARK: Grade buttons

  private var gradeButtons: some View {
    HStack(spacing: 12) {
      Button(action: { if showingAnswer { onGrade(.stillLearning) } }) {
        Label("Still learning", systemImage: "arrow.counterclockwise")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .tint(.red)
      .keyboardShortcut(.leftArrow, modifiers: [])

      Button(action: { if showingAnswer { onGrade(.known) } }) {
        Label("I know it", systemImage: "checkmark")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .tint(.green)
      .keyboardShortcut(.rightArrow, modifiers: [])
    }
    .controlSize(.large)
    .padding(.top, 8)
    .disabled(!showingAnswer)  // can't grade until the card is flipped
  }

  // MARK: Overlays

  private var dismissButton: some View {
    VStack {
      HStack {
        Spacer()
        Button(action: onDismiss) {
          Image(systemName: "xmark")
            .imageScale(.small)
            .foregroundStyle(.secondary)
            .padding(8)
        }
        .buttonStyle(.plain)
      }
      Spacer()
    }
    .padding(6)
  }

  private var boxDot: some View {
    VStack {
      Spacer()
      HStack {
        Circle()
          .fill(boxColor)
          .frame(width: 8, height: 8)
        Spacer()
      }
    }
    .padding(10)
  }

  private var boxColor: Color {
    switch card.srs.box {
    case 0: return .red
    case 1: return .orange
    case 2: return .yellow
    case 3: return .blue
    case 4: return .indigo
    default: return .green
    }
  }

  // Invisible buttons that register Space (flip) and Esc (dismiss) so the
  // popup grades from the keyboard once it becomes the key window.
  private var keyboardShortcuts: some View {
    ZStack {
      Button(action: flip) {}
        .keyboardShortcut(.space, modifiers: [])
      Button(action: onDismiss) {}
        .keyboardShortcut(.escape, modifiers: [])
    }
    .opacity(0)
    .frame(width: 0, height: 0)
  }

  private func flip() {
    withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
      showingAnswer.toggle()
    }
  }
}

#Preview("Front prompt") {
  CardView(
    card: Card(front: "Bonjour", back: "Hello"),
    promptSide: .front,
    onGrade: { _ in }, onDismiss: {})
}

#Preview("Back prompt") {
  CardView(
    card: Card(front: "Bonjour", back: "Hello"),
    promptSide: .back,
    onGrade: { _ in }, onDismiss: {})
}

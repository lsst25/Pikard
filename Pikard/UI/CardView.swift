import SwiftUI

struct CardView: View {

  let card: Card
  let deckName: String
  /// How many Leitner boxes are configured, so the box dot's colour ramp spans
  /// the whole ladder.
  let boxCount: Int
  /// Position within a batch run, e.g. "2/5". Nil when batching is off.
  let batchLabel: String?
  let onGrade: (Grade) -> Void
  let onDismiss: () -> Void

  /// Whether the prompt (question) face is the card's front. `.random` is
  /// resolved once per popup, in init.
  private let promptIsFront: Bool

  @State private var showingAnswer = false

  init(
    card: Card,
    deckName: String,
    promptSide: Deck.PromptSide = .front,
    boxCount: Int = AppSettings.defaultBoxIntervals.count,
    batchLabel: String? = nil,
    onGrade: @escaping (Grade) -> Void,
    onDismiss: @escaping () -> Void
  ) {
    self.card = card
    self.deckName = deckName
    self.boxCount = boxCount
    self.batchLabel = batchLabel
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
      deckLabel
      dismissButton
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
      Text("Click to flip")
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

      Button(action: { if showingAnswer { onGrade(.known) } }) {
        Label("I know it", systemImage: "checkmark")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .tint(.green)
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

  private var deckLabel: some View {
    VStack {
      HStack(spacing: 6) {
        Text(deckName)
          .font(.caption)
          .fontWeight(.medium)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.tail)
        if let batchLabel {
          Text(batchLabel)
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(.tertiary)
            .layoutPriority(1)
        }
        Spacer(minLength: 0)
      }
      Spacer(minLength: 0)
    }
    .padding(.top, 12)
    .padding(.leading, 14)
    .padding(.trailing, 40)  // leave room for the close button
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
    BoxColor.color(box: card.srs.box, boxCount: boxCount)
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
    deckName: "French Basics",
    promptSide: .front,
    onGrade: { _ in }, onDismiss: {})
}

#Preview("Back prompt") {
  CardView(
    card: Card(front: "Bonjour", back: "Hello"),
    deckName: "French Basics",
    promptSide: .back,
    onGrade: { _ in }, onDismiss: {})
}

#Preview("In a batch") {
  CardView(
    card: Card(front: "Bonjour", back: "Hello"),
    deckName: "French Basics",
    promptSide: .front,
    batchLabel: "2/5",
    onGrade: { _ in }, onDismiss: {})
}

import SwiftUI

// MARK: - Study window root

/// A normal, persistent window for deliberately working through cards — pick a
/// deck (or all decks), flip, and grade. Grading hits the same SRS path as the
/// popup, so a study session moves a card's learning state exactly like a popup
/// card would. Operable entirely by keyboard: Space flips, ← / → browse, and
/// 1 / 2 grade once the answer is showing.
struct StudyView: View {

  @ObservedObject var appState: AppState
  @StateObject private var session: StudySession
  @FocusState private var keyboardFocused: Bool

  init(appState: AppState) {
    self.appState = appState
    _session = StateObject(wrappedValue: StudySession(appState: appState))
  }

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      content
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }
    .frame(minWidth: 420, minHeight: 420)
    .focusable()
    .focused($keyboardFocused)
    .focusEffectDisabled()
    .onAppear { keyboardFocused = true }
    // Re-assert focus after a button click moves it, so the keyboard keeps
    // working without the user having to click the background first.
    .onChange(of: session.index) { keyboardFocused = true }
    .onChange(of: session.showingAnswer) { keyboardFocused = true }
    .onChange(of: session.finished) { keyboardFocused = true }
    // Selecting a deck in the menu Picker moves focus off the root view; the
    // queue may rebuild to the same index/state, so re-assert focus on scope too.
    .onChange(of: session.scope) { keyboardFocused = true }
    .onKeyPress(.space) { handleFlipKey() }
    .onKeyPress(.return) { handleFlipKey() }
    .onKeyPress(.leftArrow) { handleNavKey(forward: false) }
    .onKeyPress(.rightArrow) { handleNavKey(forward: true) }
    .onKeyPress("1") { handleGradeKey(.stillLearning) }
    .onKeyPress("2") { handleGradeKey(.known) }
  }

  // MARK: Header

  private var header: some View {
    HStack(spacing: 12) {
      Picker("Studying", selection: scopeBinding) {
        ForEach(scopeChoices) { choice in
          Text(choice.label).tag(choice.scope)
        }
      }
      .labelsHidden()
      .pickerStyle(.menu)
      .fixedSize()

      Spacer()

      if !session.isEmpty && !session.finished {
        Text("\(session.position) / \(session.count)")
          .font(.callout)
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
  }

  // MARK: Content states

  @ViewBuilder
  private var content: some View {
    if session.isEmpty {
      StudyEmptyView(hasDecks: !appState.decks.isEmpty)
    } else if session.finished {
      StudySummaryView(
        gradedCount: session.gradedCardIds.count,
        totalCount: session.count,
        onStudyAgain: { session.restart() })
    } else {
      activeSession
    }
  }

  private var activeSession: some View {
    VStack(spacing: 18) {
      if let card = session.currentCard, let item = session.currentItem {
        StudyCardView(
          card: card,
          deckName: item.deckName,
          promptIsFront: item.promptIsFront,
          showingAnswer: session.showingAnswer,
          onFlip: { session.flip() })
          // Fresh identity per card so a card change is an instant swap, not an
          // animated flip-back inherited from the previous card's flip state.
          .id(item.cardId)
      } else {
        // The card vanished mid-session (deleted in the deck manager). Skip
        // (in the controls below) always moves on, so this is never a dead end.
        ContentUnavailableView(
          "Card unavailable",
          systemImage: "questionmark.square.dashed",
          description: Text("This card was removed. Use Skip to continue."))
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      controls
    }
  }

  // MARK: Controls

  private var controls: some View {
    HStack(spacing: 12) {
      Button(action: { session.previous() }) {
        Image(systemName: "chevron.left")
          .frame(width: 28)
      }
      .buttonStyle(.bordered)
      .controlSize(.large)
      .disabled(session.isAtStart)
      .help("Previous card (←)")

      if session.currentCard == nil {
        Button(action: { session.skip() }) {
          Label("Skip", systemImage: "forward.fill")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .help("Skip this missing card (→)")
      } else if session.showingAnswer {
        gradeButtons
      } else {
        Button(action: { session.flip() }) {
          Label("Show answer", systemImage: "arrow.2.squarepath")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .help("Flip the card (Space)")
      }

      Button(action: { session.next() }) {
        Image(systemName: "chevron.right")
          .frame(width: 28)
      }
      .buttonStyle(.bordered)
      .controlSize(.large)
      .disabled(session.isAtEnd)
      .help("Next card (→)")
    }
  }

  private var gradeButtons: some View {
    HStack(spacing: 12) {
      Button(action: { session.grade(.stillLearning) }) {
        Label("Still learning", systemImage: "arrow.counterclockwise")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .tint(.red)
      .help("Still learning (1)")

      Button(action: { session.grade(.known) }) {
        Label("I know it", systemImage: "checkmark")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .tint(.green)
      .help("I know it (2)")
    }
    .controlSize(.large)
  }

  // MARK: Picker plumbing

  private var scopeBinding: Binding<StudyScope> {
    Binding(get: { session.scope }, set: { session.setScope($0) })
  }

  private struct ScopeChoice: Identifiable {
    let scope: StudyScope
    let label: String
    var id: StudyScope { scope }
  }

  private var scopeChoices: [ScopeChoice] {
    let total = appState.decks.reduce(0) { $0 + $1.cards.count }
    var choices = [ScopeChoice(scope: .allDecks, label: "All decks (\(total))")]
    for deck in appState.decks {
      let name = deck.name.isEmpty ? "Untitled deck" : deck.name
      choices.append(
        ScopeChoice(scope: .deck(deck.id), label: "\(name) (\(deck.cards.count))"))
    }
    return choices
  }

  // MARK: Keyboard handlers

  private func handleFlipKey() -> KeyPress.Result {
    guard canNavigate else { return .ignored }
    session.flip()  // no-ops if the live card is gone
    return .handled
  }

  private func handleNavKey(forward: Bool) -> KeyPress.Result {
    guard canNavigate else { return .ignored }
    if forward {
      // → skips past a deleted card (finishing at the end) so it's never a trap.
      session.currentCard == nil ? session.skip() : session.next()
    } else {
      session.previous()
    }
    return .handled
  }

  private func handleGradeKey(_ grade: Grade) -> KeyPress.Result {
    guard canNavigate, session.showingAnswer else { return .ignored }
    session.grade(grade)
    return .handled
  }

  /// Keys act whenever a card position is on screen — not on the empty or
  /// summary view. A position with a deleted live card still navigates (Skip).
  private var canNavigate: Bool {
    !session.isEmpty && !session.finished
  }
}

// MARK: - Card

/// The flippable card shown in the study window. Mirrors the popup `CardView`'s
/// look (background, 3-D flip, deck label, Leitner box dot) but fills the window
/// and leaves grading to the control bar below it.
private struct StudyCardView: View {

  let card: Card
  let deckName: String
  let promptIsFront: Bool
  let showingAnswer: Bool
  let onFlip: () -> Void

  private var promptText: String { promptIsFront ? card.front : card.back }
  private var answerText: String { promptIsFront ? card.back : card.front }

  var body: some View {
    ZStack {
      background

      ZStack {
        face(promptText, hint: "Click or press Space to flip", font: .largeTitle)
          .opacity(showingAnswer ? 0 : 1)
          .rotation3DEffect(
            .degrees(showingAnswer ? 180 : 0),
            axis: (x: 0, y: 1, z: 0), perspective: 0.6)

        face(answerText, hint: "1 — Still learning      2 — I know it", font: .title)
          .opacity(showingAnswer ? 1 : 0)
          .rotation3DEffect(
            .degrees(showingAnswer ? 0 : -180),
            axis: (x: 0, y: 1, z: 0), perspective: 0.6)
      }

      deckLabel
      boxDot
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .contentShape(Rectangle())
    .onTapGesture { onFlip() }
    .animation(.spring(response: 0.5, dampingFraction: 0.7), value: showingAnswer)
  }

  private func face(_ text: String, hint: String, font: Font) -> some View {
    VStack(spacing: 16) {
      Spacer()
      Text(text)
        .font(font)
        .multilineTextAlignment(.center)
        .lineLimit(8)
        .minimumScaleFactor(0.5)
      Text(hint)
        .font(.caption)
        .foregroundStyle(.tertiary)
      Spacer()
    }
    .padding(.horizontal, 28)
  }

  private var background: some View {
    RoundedRectangle(cornerRadius: 16, style: .continuous)
      .fill(.background)
      .overlay(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .stroke(Color.primary.opacity(0.08), lineWidth: 1))
  }

  private var deckLabel: some View {
    VStack {
      HStack {
        Text(deckName.isEmpty ? "Untitled deck" : deckName)
          .font(.caption)
          .fontWeight(.medium)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.tail)
        Spacer(minLength: 0)
      }
      Spacer(minLength: 0)
    }
    .padding(16)
  }

  private var boxDot: some View {
    VStack {
      Spacer()
      HStack {
        Circle()
          .fill(StudyView.boxColor(card.srs.box))
          .frame(width: 9, height: 9)
          .help("Leitner box \(card.srs.box)")
        Spacer()
      }
    }
    .padding(14)
  }
}

// MARK: - Empty / summary

private struct StudyEmptyView: View {
  let hasDecks: Bool

  var body: some View {
    ContentUnavailableView(
      hasDecks ? "No cards to study" : "No decks yet",
      systemImage: hasDecks ? "rectangle.on.rectangle.slash" : "rectangle.stack.badge.plus",
      description: Text(
        hasDecks
          ? "This deck has no cards. Pick another deck above, or add cards in Manage Decks."
          : "Import a deck first, then come back to study."))
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

private struct StudySummaryView: View {
  let gradedCount: Int
  let totalCount: Int
  let onStudyAgain: () -> Void

  var body: some View {
    VStack(spacing: 20) {
      Spacer()
      Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 52))
        .foregroundStyle(.green)
      Text("Session complete")
        .font(.title2.weight(.semibold))
      Text(summaryText)
        .font(.body)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
      Button(action: onStudyAgain) {
        Label("Study again", systemImage: "arrow.clockwise")
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
      .padding(.top, 4)
      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var summaryText: String {
    let cards = gradedCount == 1 ? "card" : "cards"
    return "You graded \(gradedCount) \(cards) of \(totalCount)."
  }
}

// MARK: - Shared

extension StudyView {
  /// Leitner-box colour, matching the popup card's box dot.
  static func boxColor(_ box: Int) -> Color {
    switch box {
    case 0: return .red
    case 1: return .orange
    case 2: return .yellow
    case 3: return .blue
    case 4: return .indigo
    default: return .green
    }
  }
}

#Preview {
  StudyView(appState: AppState())
    .frame(width: 460, height: 460)
}

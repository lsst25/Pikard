import SwiftUI

struct ImportWindowView: View {

  @ObservedObject var appState: AppState
  let onClose: () -> Void

  @State private var deckName: String = ""
  @State private var pastedText: String = ""
  @State private var lastImport: ImportSummary? = nil

  private var parsedCount: Int {
    QuizletParser.parse(pastedText).count
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      header

      deckNameRow

      Text("Paste your Quizlet export below:")
        .foregroundStyle(.secondary)

      TextEditor(text: $pastedText)
        .font(.system(.body, design: .monospaced))
        .frame(minHeight: 200)
        .overlay(
          RoundedRectangle(cornerRadius: 6)
            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
        )

      footer
    }
    .padding(20)
    .frame(minWidth: 480, minHeight: 360)
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Import deck")
        .font(.title2)
        .fontWeight(.semibold)
      if let summary = lastImport {
        Text(summary.message)
          .font(.subheadline)
          .foregroundStyle(summary.isError ? .red : .secondary)
      }
    }
  }

  private var deckNameRow: some View {
    HStack {
      Text("Name:")
        .frame(width: 60, alignment: .trailing)
      TextField("e.g. French Greetings", text: $deckName)
        .textFieldStyle(.roundedBorder)
    }
  }

  private var footer: some View {
    HStack {
      Text(statusText)
        .foregroundStyle(.secondary)
      Spacer()
      Button("Cancel", action: onClose)
        .keyboardShortcut(.cancelAction)

      Button("Import", action: performImport)
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
        .disabled(!canImport)
    }
  }

  private var statusText: String {
    if pastedText.isEmpty { return "Paste cards above to preview." }
    if parsedCount == 0 { return "Couldn't find any cards in the pasted text." }
    return "Found \(parsedCount) cards."
  }

  private var canImport: Bool {
    !deckName.trimmingCharacters(in: .whitespaces).isEmpty && parsedCount > 0
  }

  private func performImport() {
    let trimmedName = deckName.trimmingCharacters(in: .whitespaces)
    let n = appState.importDeck(named: trimmedName, fromQuizletText: pastedText)
    lastImport = ImportSummary(parsed: n, deck: trimmedName)
    deckName = ""
    pastedText = ""
  }
}

private struct ImportSummary {
  let parsed: Int
  let deck: String
  var isError: Bool { parsed == 0 }
  var message: String {
    parsed == 0
      ? "No cards imported."
      : "Imported \(parsed) cards into \"\(deck)\"."
  }
}

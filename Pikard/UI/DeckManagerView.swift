import SwiftUI

// MARK: - Deck Manager (master/detail)

struct DeckManagerView: View {

  @ObservedObject var appState: AppState
  @State private var selection: UUID?
  @State private var pendingDeleteDeck: UUID?
  @State private var pendingDeleteName: String = ""

  var body: some View {
    NavigationSplitView {
      List(selection: $selection) {
        ForEach(appState.decks) { deck in
          deckRow(deck).tag(deck.id)
        }
      }
      .frame(minWidth: 200)
      .navigationTitle("Decks")
      .toolbar {
        ToolbarItemGroup {
          Button(action: addDeck) {
            Image(systemName: "plus")
          }
          .help("New deck")

          Button {
            if let id = selection { requestDelete(id) }
          } label: {
            Image(systemName: "minus")
          }
          .help("Delete selected deck")
          .disabled(selection == nil)
        }
      }
    } detail: {
      if let id = selection, appState.decks.contains(where: { $0.id == id }) {
        DeckDetailView(appState: appState, deckID: id)
          .id(id)
      } else {
        ContentUnavailableView(
          "No deck selected",
          systemImage: "rectangle.stack",
          description: Text("Select a deck on the left, or press + to create one."))
      }
    }
    .frame(minWidth: 680, minHeight: 460)
    .confirmationDialog(
      "Delete this deck and all its cards?",
      isPresented: Binding(
        get: { pendingDeleteDeck != nil },
        set: { if !$0 { pendingDeleteDeck = nil } }),
      titleVisibility: .visible
    ) {
      Button("Delete", role: .destructive) {
        if let id = pendingDeleteDeck {
          appState.deleteDeck(id: id)
          if selection == id { selection = nil }
        }
        pendingDeleteDeck = nil
      }
      Button("Cancel", role: .cancel) { pendingDeleteDeck = nil }
    } message: {
      Text("\"\(pendingDeleteName)\" will be removed. This cannot be undone.")
    }
  }

  private func requestDelete(_ id: UUID) {
    let deck = appState.decks.first { $0.id == id }
    pendingDeleteName = (deck?.name.isEmpty == false ? deck?.name : nil) ?? "Untitled deck"
    pendingDeleteDeck = id
  }

  private func deckRow(_ deck: Deck) -> some View {
    HStack(spacing: 8) {
      Image(systemName: deck.isActive ? "checkmark.circle.fill" : "circle")
        .foregroundStyle(deck.isActive ? .green : .secondary)
        .help(deck.isActive ? "Active in rotation" : "Paused")
      Text(deck.name.isEmpty ? "Untitled deck" : deck.name)
        .lineLimit(1)
      Spacer()
      Text("\(deck.cards.count)")
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }
    .contextMenu {
      Button("Delete deck", role: .destructive) { requestDelete(deck.id) }
    }
  }

  private func addDeck() {
    selection = appState.createDeck()
  }
}

// MARK: - Deck detail

struct DeckDetailView: View {

  @ObservedObject var appState: AppState
  let deckID: UUID

  @State private var name: String = ""

  private var deck: Deck? { appState.decks.first { $0.id == deckID } }

  var body: some View {
    if let deck {
      VStack(alignment: .leading, spacing: 12) {
        header(deck)
        Divider()
        cardList(deck)
        footer(deck)
      }
      .padding()
      .navigationTitle(deck.name.isEmpty ? "Untitled deck" : deck.name)
      .onAppear { name = deck.name }
      .onChange(of: deck.name) { _, newValue in
        // Resync if the name changed from outside this field.
        if newValue != name { name = newValue }
      }
    } else {
      ContentUnavailableView(
        "Deck deleted", systemImage: "trash",
        description: Text("This deck no longer exists."))
    }
  }

  private func header(_ deck: Deck) -> some View {
    HStack(spacing: 12) {
      TextField("Deck name", text: $name)
        .textFieldStyle(.roundedBorder)
        .font(.title3)
        .onChange(of: name) { _, value in
          appState.setDeckName(id: deckID, to: value)
        }

      Picker(
        "Show",
        selection: Binding(
          get: { deck.promptSide },
          set: { appState.setDeckPromptSide(id: deckID, to: $0) })
      ) {
        ForEach(Deck.PromptSide.allCases) { side in
          Text(side.displayName).tag(side)
        }
      }
      .pickerStyle(.menu)
      .fixedSize()
      .help("Which side of the card shows first when it pops up")

      Toggle(
        "Active",
        isOn: Binding(
          get: { deck.isActive },
          set: { appState.setDeckActive(id: deckID, to: $0) })
      )
      .toggleStyle(.switch)
      .help("Include this deck in the popup rotation")
    }
  }

  private func cardList(_ deck: Deck) -> some View {
    Group {
      if deck.cards.isEmpty {
        ContentUnavailableView(
          "No cards yet", systemImage: "plus.rectangle.on.rectangle",
          description: Text("Add a card below, or use Import deck… for bulk paste."))
      } else {
        ScrollView {
          LazyVStack(spacing: 8) {
            ForEach(deck.cards) { card in
              CardRowEditor(
                card: card,
                onChange: { front, back in
                  appState.setCardText(
                    cardId: card.id, in: deckID, front: front, back: back)
                },
                onDelete: { appState.deleteCard(id: card.id, in: deckID) }
              )
              .id(card.id)
            }
          }
          .padding(.vertical, 4)
        }
      }
    }
    .frame(maxHeight: .infinity)
  }

  private func footer(_ deck: Deck) -> some View {
    HStack {
      Button {
        appState.addCard(to: deckID)
      } label: {
        Label("Add card", systemImage: "plus")
      }
      Spacer()
      Text("\(deck.cards.count) card(s)")
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }
  }
}

// MARK: - Card row editor

struct CardRowEditor: View {

  let card: Card
  let onChange: (String, String) -> Void
  let onDelete: () -> Void

  @State private var front: String
  @State private var back: String

  init(
    card: Card,
    onChange: @escaping (String, String) -> Void,
    onDelete: @escaping () -> Void
  ) {
    self.card = card
    self.onChange = onChange
    self.onDelete = onDelete
    _front = State(initialValue: card.front)
    _back = State(initialValue: card.back)
  }

  var body: some View {
    HStack(spacing: 8) {
      Circle()
        .fill(boxColor)
        .frame(width: 7, height: 7)
        .help("Leitner box \(card.srs.box)")

      TextField("Front", text: $front)
        .textFieldStyle(.roundedBorder)
        .onChange(of: front) { _, value in onChange(value, back) }

      TextField("Back", text: $back)
        .textFieldStyle(.roundedBorder)
        .onChange(of: back) { _, value in onChange(front, value) }

      Button(role: .destructive, action: onDelete) {
        Image(systemName: "trash")
      }
      .buttonStyle(.borderless)
      .help("Delete card")
    }
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
}

#Preview {
  DeckManagerView(appState: AppState())
}

// AppDelegate.swift
import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {

  private let appState = AppState()
  private let popup = PopupController()
  private lazy var scheduler = PopupScheduler(appState: appState, popup: popup)

  private var statusItem: NSStatusItem?
  private var cancellables: Set<AnyCancellable> = []

  private var importController: ImportWindowController?
  private var settingsController: SettingsWindowController?
  private var deckManagerController: DeckManagerWindowController?
  private var studyController: StudyWindowController?

  private static let timeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .none
    f.timeStyle = .short
    return f
  }()

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApplication.shared.setActivationPolicy(.accessory)
    setUpStatusItem()

    // Rebuild the menu and refresh the title whenever the decks change.
    appState.$decks
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in
        self?.rebuildMenu()
        self?.refreshStatusBarTitle()
      }
      .store(in: &cancellables)

    // Rebuild the menu whenever scheduler state changes (pause/resume/next-fire).
    Publishers.CombineLatest3(
      scheduler.$isRunning,
      scheduler.$pausedUntil,
      scheduler.$nextFire
    )
    .receive(on: RunLoop.main)
    .sink { [weak self] _, _, _ in self?.rebuildMenu() }
    .store(in: &cancellables)

    // When the interval changes, recompute the next deadline immediately.
    appState.$settings
      .map(\.intervalMinutes)
      .removeDuplicates()
      .dropFirst()
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in self?.scheduler.fireNowOrReschedule() }
      .store(in: &cancellables)

    // Keep the login-item registration in sync with the setting.
    appState.$settings
      .map(\.launchAtLogin)
      .removeDuplicates()
      .receive(on: RunLoop.main)
      .sink { [weak self] enabled in self?.applyLaunchAtLogin(enabled) }
      .store(in: &cancellables)

    refreshStatusBarTitle()
    scheduler.start()
  }

  func applicationWillTerminate(_ notification: Notification) {
    appState.flush()  // force any debounced deck/settings edits to disk
  }

  // MARK: Status item

  private func setUpStatusItem() {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    if let button = item.button {
      button.image = NSImage(
        systemSymbolName: "rectangle.stack", accessibilityDescription: "Pikard")
      button.image?.isTemplate = true
      button.imagePosition = .imageLeading
    }
    let menu = NSMenu()
    menu.delegate = self
    populate(menu)
    item.menu = menu
    statusItem = item
  }

  private func refreshStatusBarTitle() {
    let due = SRSAlgorithm.dueCount(decks: appState.decks)
    statusItem?.button?.title = due > 0 ? "  \(due)" : ""
  }

  /// Repopulate the status-item menu in place (never swap the instance, which
  /// would break a menu that is mid-open).
  private func rebuildMenu() {
    guard let menu = statusItem?.menu else { return }
    populate(menu)
  }

  // MARK: Menu

  private func populate(_ menu: NSMenu) {
    menu.removeAllItems()

    if appState.decks.isEmpty {
      let empty = NSMenuItem(title: "No decks yet", action: nil, keyEquivalent: "")
      empty.isEnabled = false
      menu.addItem(empty)
    } else {
      for deck in appState.decks {
        let prefix = deck.isActive ? "✓" : "○"
        let name = deck.name.isEmpty ? "Untitled deck" : deck.name
        let item = NSMenuItem(
          title: "\(prefix)  \(name)  (\(deck.cards.count))",
          action: #selector(toggleDeck(_:)),
          keyEquivalent: "")
        item.target = self
        item.representedObject = deck.id
        menu.addItem(item)
      }
    }

    menu.addItem(.separator())

    let nowItem = NSMenuItem(
      title: "Show next card now", action: #selector(showNextCardNow), keyEquivalent: "")
    nowItem.target = self
    menu.addItem(nowItem)

    let studyItem = NSMenuItem(
      title: "Study…", action: #selector(openStudy), keyEquivalent: "s")
    studyItem.target = self
    menu.addItem(studyItem)

    let statusRow = NSMenuItem(title: nextFireLabel, action: nil, keyEquivalent: "")
    statusRow.isEnabled = false
    menu.addItem(statusRow)

    let isPaused = scheduler.pausedUntil != nil
    let pauseItem = NSMenuItem(
      title: isPaused ? "Resume" : "Pause",
      action: isPaused ? #selector(resumeSchedule) : #selector(pauseSchedule),
      keyEquivalent: "")
    pauseItem.target = self
    menu.addItem(pauseItem)

    menu.addItem(skipMenuItem())

    menu.addItem(.separator())

    let manageItem = NSMenuItem(
      title: "Manage decks…", action: #selector(openDeckManager), keyEquivalent: "d")
    manageItem.target = self
    menu.addItem(manageItem)

    let importItem = NSMenuItem(
      title: "Import deck…", action: #selector(openImportWindow), keyEquivalent: "i")
    importItem.target = self
    menu.addItem(importItem)

    let settingsItem = NSMenuItem(
      title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
    settingsItem.target = self
    menu.addItem(settingsItem)

    menu.addItem(.separator())
    menu.addItem(
      withTitle: "Quit Pikard",
      action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q")
  }

  private func skipMenuItem() -> NSMenuItem {
    guard let until = scheduler.pausedUntil, until > Date() else {
      let item = NSMenuItem(
        title: "Skip next hour", action: #selector(skipHour), keyEquivalent: "")
      item.target = self
      return item
    }
    // Indefinite pause uses a far-future sentinel; show a readable label.
    let title =
      until > Date().addingTimeInterval(86_400)
      ? "Paused indefinitely"
      : "Skipping until \(Self.timeFormatter.string(from: until))"
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    item.isEnabled = false
    return item
  }

  private var nextFireLabel: String {
    guard scheduler.isRunning else { return "Schedule stopped" }
    if scheduler.pausedUntil != nil { return "Paused" }
    guard let next = scheduler.nextFire else { return "Schedule stopped" }
    let minutes = Int(next.timeIntervalSinceNow / 60)
    if minutes < 1 { return "Next card any moment" }
    return "Next card in \(minutes) min"
  }

  // MARK: Actions

  @objc private func showNextCardNow() {
    // One shared path with the timer-driven popup: batching, grading and the
    // cadence reset all live in the scheduler.
    if scheduler.showCardRun() { return }

    let message =
      appState.decks.isEmpty
      ? "Import a deck to get started."
      : caughtUpLabel()
    popup.showEmptyState(message: message, corner: appState.settings.popupCorner)
  }

  private func caughtUpLabel() -> String {
    // Nothing was shown, so nothing is due: report when the next card *becomes*
    // due, which is what the user is actually waiting on.
    guard let due = SRSAlgorithm.nextDueDate(decks: appState.decks) else {
      return "All caught up."
    }
    let seconds = due.timeIntervalSinceNow
    if seconds < 60 { return "All caught up — next card due any moment." }
    return "All caught up — next card due in \(Self.roughDuration(seconds))."
  }

  private static func roughDuration(_ seconds: TimeInterval) -> String {
    let minutes = Int(seconds / 60)
    if minutes < 60 { return "\(minutes) min" }
    let hours = minutes / 60
    if hours < 24 { return hours == 1 ? "1 hour" : "\(hours) hours" }
    let days = hours / 24
    return days == 1 ? "1 day" : "\(days) days"
  }

  @objc private func pauseSchedule() {
    scheduler.pausedUntil = .distantFuture  // indefinite
  }

  @objc private func resumeSchedule() {
    scheduler.resume()
  }

  @objc private func skipHour() {
    scheduler.pause(for: 3600)
  }

  @objc private func toggleDeck(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? UUID else { return }
    appState.toggleActive(deckId: id)
  }

  @objc private func openStudy() {
    if studyController == nil {
      studyController = StudyWindowController(appState: appState) { [weak self] in
        self?.studyController = nil
      }
    }
    studyController?.show()
  }

  @objc private func openDeckManager() {
    if deckManagerController == nil {
      deckManagerController = DeckManagerWindowController(appState: appState) {
        [weak self] in
        self?.deckManagerController = nil
      }
    }
    deckManagerController?.show()
  }

  @objc private func openImportWindow() {
    if importController == nil {
      importController = ImportWindowController(appState: appState) { [weak self] in
        self?.importController = nil
      }
    }
    importController?.show()
  }

  @objc private func openSettings() {
    if settingsController == nil {
      settingsController = SettingsWindowController(appState: appState) { [weak self] in
        self?.settingsController = nil
      }
    }
    settingsController?.show()
  }

  // MARK: Launch at login

  private func applyLaunchAtLogin(_ enabled: Bool) {
    do {
      try LaunchAtLogin.setEnabled(enabled)
    } catch {
      appState.lastError = "Launch-at-login change failed: \(error.localizedDescription)"
    }
  }
}

extension AppDelegate: NSMenuDelegate {
  func menuNeedsUpdate(_ menu: NSMenu) {
    // Rebuild right before the menu opens so the "Next card in N min" label and
    // the due count are fresh at the moment the user looks.
    refreshStatusBarTitle()
    populate(menu)
  }
}

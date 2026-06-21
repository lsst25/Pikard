# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Pikard is a menu-bar-only macOS spaced-repetition flashcard app (SwiftUI + AppKit). It periodically pops a card into a screen corner, you grade it (Known / Still learning / dismiss), and a Leitner-box scheduler decides what to show next. There is also an on-demand "Study" window for working through a deck deliberately. The app has no main window — it lives entirely in the status bar.

## Build, install, test

```bash
# Build + ad-hoc sign + install to /Applications + relaunch (no Apple Developer account needed)
./install.sh
./install.sh --no-open          # build & install, don't launch

# Plain build / test via Xcode
xcodebuild -scheme Pikard -configuration Debug -destination 'platform=macOS' build
xcodebuild test -scheme Pikard -destination 'platform=macOS'

# Run a single test (target/class/method)
xcodebuild test -scheme Pikard -destination 'platform=macOS' \
  -only-testing:PikardTests/QuizletParserTests/test_tabSeparated
```

`install.sh` builds Release with manual signing (`CODE_SIGN_IDENTITY="-"`) into a temp DerivedData dir, kills any running copy, and copies the `.app` to `/Applications`. Unit tests (`PikardTests`) cover pure logic (parser, SRS, settings, quiet hours); UI tests (`PikardUITests`) are the Xcode-generated stubs.

## Critical build constraints

- **Synchronized file groups.** The project uses `PBXFileSystemSynchronizedRootGroup` for `Pikard/`, `PikardTests/`, `PikardUITests/`. Sources are added to the target **by filesystem location** — a new `.swift` file is compiled iff it lives under one of these dirs. Never edit `project.pbxproj` to add files; just create them in the right folder. A file placed anywhere else is **silently not compiled**.
- **Sandbox is OFF** (`ENABLE_APP_SANDBOX = NO`), required for the private screen-watch symbol and for writing the launch-at-login plist.
- Menu-bar-only: `INFOPLIST_KEY_LSUIElement = YES` + `setActivationPolicy(.accessory)`. Bundle id `dev.lsst.Pikard`, deployment target macOS 26.3, Swift 5.

## Architecture

Everything is driven by `AppDelegate` (via `@NSApplicationDelegateAdaptor`); `PikardApp`'s SwiftUI `Scene` is just an empty `Settings {}` placeholder. `AppDelegate` owns the status item + menu, wires Combine subscriptions, and lazily creates the AppKit window controllers.

**Data flow / single source of truth — `AppState` (`@MainActor ObservableObject`)**
- Holds `decks: [Deck]` and `settings: AppSettings`; every mutation routes through it and persists.
- Persistence is `Store<T: Codable>` → JSON under `~/Library/Application Support/Pikard/` (`decks.json`, `settings.json`). If Application Support is unavailable it falls back to a temp-dir store so the session still works.
- High-frequency edits (typing card/deck text) go through a debounced `saveTrigger`; structural changes call `persist()` immediately. `flush()` forces pending writes on quit/window-close.

**Scheduling — `PopupScheduler` (`@MainActor`)**
- Holds exactly one pending one-shot `DispatchSourceTimer` aimed at the next fire, and reschedules itself after each fire. Not a repeating timer.
- Every fire re-checks all gates before showing a card: running, `pausedUntil`, quiet hours, **screen sharing**, and popup-already-visible. Delay = `intervalMinutes` ± jitter (`jitterFraction`).
- Re-fires on `NSWorkspace.didWakeNotification` since GCD timers don't catch up after sleep.

**SRS — `SRSAlgorithm` (pure, stateless enum)**
- Leitner system: 6 boxes, intervals 5 min → 7 days. `grade()` moves a card up/down a box; `selectNextCard()` picks the oldest-due card (random among ties) from active decks; `dueCount()` feeds the menu-bar badge. All take an injectable `now:` for testability.

**Study window — `StudySession` (`@MainActor`)**
- Builds a **snapshot** queue ordered by due date for a `StudyScope` (all decks or one). Unlike the popup, it ignores `isActive`. Grading routes through `AppState.grade` — the *same* SRS state the popups update — but re-fetches the live card each time so the box shown is current. Queue only reshuffles on explicit "Study again".

**Popup presentation — `PopupController` + `PopupPanel`**
- A non-activating, borderless, floating `NSPanel` that never steals focus from the foreground app. `PopupHostingView` overrides `acceptsFirstMouse` so a single click hits a grade button even while Pikard is inactive. A global click monitor dismisses on outside-click. Slide+fade in/out animations; `dismiss()` is idempotent.

**Platform integration**
- `ScreenShareDetector`: reads the private `CGSIsScreenWatcherPresent` / `SLSIsScreenWatcherPresent` symbol (resolved once via `dlsym(RTLD_DEFAULT)`) to suppress popups during screen-sharing/recording. **Fails open** (reports "not capturing") if the symbol ever disappears.
- `LaunchAtLogin`: writes a per-user LaunchAgent plist to `~/Library/LaunchAgents/dev.lsst.Pikard.plist`. Deliberately **not** `SMAppService`, which refuses to register ad-hoc-signed local builds. It does not `bootstrap` on enable (would spawn a duplicate); the agent loads at next login.

**UI layer** (`Pikard/UI/`): each window is an AppKit `*WindowController` hosting a SwiftUI view (`StudyView`, `DeckManagerView`, `ImportWindow`, `SettingsWindow`, plus the popup's `CardView` / `EmptyStateView`). Controllers call back to `AppDelegate` to clear their reference on close.

**Import — `QuizletParser`** parses pasted Quizlet exports: auto-detects field separator (tab → comma → semicolon), normalizes line endings, joins overflow fields, and `merge()` dedupes against an existing deck by lowercased `front|back`.

## Conventions worth following

- **Codable migration for persisted models.** When adding a field to a model that's saved to disk, decode it with `decodeIfPresent(...) ?? default` so older JSON still loads. `Deck.init(from:)` is the worked example (it back-fills `promptSide`).
- Keep SRS/scheduling logic pure with an injectable `now: Date = Date()` — that's what makes it unit-testable without waiting on wall-clock time.
- Both the passive popup and the Study window grade through `AppState.grade`; keep that single path so the two views never diverge on SRS state.

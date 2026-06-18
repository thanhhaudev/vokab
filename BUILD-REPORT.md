# vokab — Build Report

Status of the initial end-to-end build. Generated 2026-06-16.

## Summary

A native macOS SwiftUI **menubar agent** that captures vocabulary, analyzes it with the `agy` CLI, stores it in SQLite (GRDB), and reviews it with SM-2 spaced repetition. The engine is fully tested; the app compiles, is ad-hoc code-signed, and launches as a background agent.

- **Build:** `Release` builds and is **ad-hoc signed** (`Signature=adhoc`, `TeamIdentifier=not set` — no personal identity committed).
- **Tests:** 51 offline unit tests + 6 real-`agy` integration tests, all passing.
- **Launch:** app runs as an `LSUIElement` accessory (menubar, no Dock icon).

## How to build & run

```bash
brew install xcodegen
cd App && xcodegen generate
# ad-hoc signed (no Apple account needed)
xcodebuild -project vokab.xcodeproj -scheme vokab -configuration Release \
  CODE_SIGN_IDENTITY="-" build
open ../$(...)/Release/vokab.app   # or open vokab.xcodeproj in Xcode
```

Tests:
```bash
swift test                              # offline unit tests (no agy)
VOKAB_AGY_INTEGRATION=1 swift test      # + real-agy contract tests
```

Headless wiring check:
```bash
BIN=.../vokab.app/Contents/MacOS/vokab
VOKAB_SELFTEST=1 VOKAB_SEED=1 VOKAB_DB=/tmp/v.sqlite "$BIN"   # prints entries/due counts
```

## Per-phase status

| Phase | Scope | Status | Verification |
|---|---|---|---|
| 0 | Scaffold (package, xcodegen app, CI) | ✅ Done | xcodegen + swift build + empty app compile |
| 1 | agy wrapper, models, 4 templates | ✅ Done & verified | 22 offline + 4 real-agy contract tests |
| 2 | GRDB schema/repos, SM-2 | ✅ Done & verified | migration/repository/SM-2 unit tests |
| 3 | Capture pipeline (classify/cache/quota) | ✅ Done & verified | offline + real capture-to-DB integration |
| 4 | Core UI (Library, details, flashcard) | ✅ Done | builds, launches, self-test reads seeded DB |
| 5 | Menubar agent, toast, notifications | ✅ Done | launches as accessory agent |
| 6 | NSServices "Capture to vokab" | ✅ Done | registered in macOS pasteboard-services registry |
| 7 | Production card, Settings, export | ✅ Done | builds, launches |
| Final | Ad-hoc Release build, suites, report | ✅ Done | signed Release app + all suites green |

## Verified vs. requires human GUI confirmation

**Automatically verified:** engine logic (offline), real-agy decoding of all 4 templates, capture→DB round-trip, ad-hoc signature validity, app launch as agent, DB read path through the full app stack, NSServices registration.

**Best confirmed by a person (GUI interactions):**
- Clicking the **menubar** item and seeing the popover / due count render.
- Selecting text in another app → **Services → "Capture to vokab"** → toast + entry created (registration is verified; the click-through is manual).
- The capture **toast** and **notification** action buttons (View/Undo).
- The **production card** writing flow (only reachable once a card matures: `interval ≥ 7` and `≥ 2` recognitions — seed data is not yet mature; capture a word and grade it forward, or it can be exercised via a real review session over time).

## Recent additions (paragraph extraction + master-detail)

- **Paragraph extraction** (SPEC surface #3) — capturing a paragraph now opens an extraction window: candidate words as a checklist (CEFR/meaning/reason), already-saved words pre-unchecked (dedupe), "Select all" / "Add N to deck" → persists chosen items. The toast's **View** reopens it (fixes the prior View → empty-Library dead end).
- **Master-detail Library** — replaced the detail popup with an inline 3-pane layout (filters | word list | detail pane); selecting a word shows its detail on the right (resets + lazy-enriches per selection), delete lives in the pane. Library window widened to 1060×640.

## Recent additions (speed: two-tier capture)

- **Two-tier capture** — capture asks agy only **core** fields (faster toast/library/review); **enrichment** fields (etymology, synonyms, antonyms, word family / variations, common errors, related phrases, extra examples) are fetched **lazily** the first time a word/phrase detail opens, merged into the stored result and cached (`entries.enriched`, migration v3). Detail shows core instantly; tier-2 sections show a loading row until merged.
- Rationale: agy latency is backend-model-dominated (~2.8s local boot; the rest is generation/network), so generating fewer fields at capture is the real speed lever. A warm-session approach was investigated and rejected (agy interactive is a TUI; warm would save only ~2.8s). See `docs/superpowers/DECISIONS.md` (local).

## Recent additions (UX + settings)

- **Delete a word** — Library row context menu + detail-sheet trash, behind a confirmation dialog.
- **Stacked capture toasts** — rapid captures each get their own toast (no overwrite); position configurable.
- **Correct source** — manual menubar/quick captures record "Manual entry"; Services records the real app.
- **Settings tabs** — General (launch at login, toast position, opt-in global hotkey), Review (new cards/day, production unlock thresholds, starting ease), Capture (auto-detect language + default, min paragraph CEFR), Export (CSV/MD/Anki). AI-Engine model picker verified against `agy --model`.
- **Day streak** + POS-derived colors (phrase tokens, formula, etymology) via on-device NaturalLanguage.
- **App language** setting (default English) with a lightweight en/vi chrome localization.

Global hotkey is opt-in (default off) and best confirmed manually (press the recorded combo → quick-capture field opens).

## Architecture notes

- `VokabKit` (SPM package) holds all logic and is offline-testable; the app target is a thin SwiftUI/AppKit layer.
- `ai_result` stores the re-encoded decoded model (round-trips through the lenient decoder). See `docs/superpowers/DECISIONS.md` (local) for the full decision log.
- Public-repo hygiene: ad-hoc signing, no `DEVELOPMENT_TEAM`; generated `.xcodeproj` is gitignored and regenerated from `App/project.yml`.

## Suggested next steps

- Human pass through the GUI interactions above.
- Tighten to Swift 6 language mode as a focused task (currently Swift 5 mode to avoid strict-concurrency churn).
- App sandbox + hardened runtime for distribution (currently disabled for local dev).
- Optional: store raw agy JSON in `ai_result` if richer fidelity than the typed models is wanted.
- Settings changes that affect services currently apply on relaunch; live-reload is a future enhancement.

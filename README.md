# vokab

> Capture vocabulary from **any** macOS app with a right-click, let an AI engine analyze it, and review it with spaced repetition — all **local**, no backend, no account.

vokab is a native macOS menubar app. Select a word, phrase, or paragraph in any application, send it to vokab via the **Services** menu, and it’s analyzed by the [`agy`](https://github.com/) CLI (CEFR level, meaning, examples, etymology…), stored in a local SQLite database, and scheduled for review with the SM-2 algorithm. Your vocabulary and where you found it never leave your machine.

## Features

- **One-gesture capture** — right-click → *Capture to vokab* from any app (uses macOS Services; no Accessibility permission needed).
- **Four card types** — single word, phrase/idiom, paragraph extraction, and production (writing) practice — each with a tailored AI analysis.
- **Spaced repetition** — SM-2 with recognition cards first, production (write-a-sentence, AI-graded) cards once a word matures.
- **All local & private** — vocabulary + source context live in SQLite on your Mac. No server.
- **Menubar agent** — lightweight background app; due-count, quick review, and daily digest in the menubar popover.

## Architecture

Native Swift/SwiftUI, all-local, **no backend**:

```
select text → Services → vokab → agy CLI → JSON → SQLite (GRDB) → SM-2 review
```

- **`VokabKit`** (Swift package) — all logic: agy wrapper, card models, GRDB storage, SM-2, capture orchestration. Unit-tested offline.
- **App target** — SwiftUI UI, menubar agent, Services handler, notifications. Thin layer over `VokabKit`.

## Requirements

- macOS 14+
- Xcode 26+
- [`agy`](https://github.com/) CLI installed and logged in (the AI engine; vokab calls it as a subprocess — there is no API-key field in the app, auth is managed by `agy`).
- [`xcodegen`](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Build

```bash
# generate the Xcode project (not committed — derived from App/project.yml)
cd App && xcodegen generate

# build (ad-hoc signed — no Apple Developer account required)
xcodebuild -project vokab.xcodeproj -scheme vokab -configuration Debug \
  build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO

# or open in Xcode
open vokab.xcodeproj
```

Run the engine/logic tests (no `agy` needed):

```bash
swift test
```

Run the real-`agy` contract tests (requires `agy` installed & logged in):

```bash
VOKAB_AGY_INTEGRATION=1 swift test
```

## Code signing

The committed project uses **ad-hoc signing** (`CODE_SIGN_IDENTITY = "-"`, no team) so anyone can clone and build locally without an Apple Developer account. To sign with your own identity, put your settings in a `*.local.xcconfig` (gitignored) — never commit a team ID.

## License

MIT — see [LICENSE](LICENSE).

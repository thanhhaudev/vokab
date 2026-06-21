# vokab

**vokab** is a macOS menubar app that bullies Antigravity (`agy`) into being a dictionary. Look up any word from any app; results are saved locally and reviewed with SM-2.

## Requirements

- macOS 14 or later.
- Antigravity (`agy`) installed at `~/.local/bin/agy` and logged in. vokab calls it as a subprocess — there is no API-key field; `agy` manages auth.
- Accessibility permission, so the capture hotkey can read your current selection.

## Install

### Download a build

1. Download the latest `vokab-<version>.dmg` from [Releases](../../releases).
2. Open it and drag **vokab.app** into **Applications**.
3. Clear the download quarantine — the app is ad-hoc signed, not notarized:
   ```bash
   xattr -dr com.apple.quarantine /Applications/vokab.app
   ```
4. Launch vokab from Applications.

### Build from source

Requires Xcode 26+ and `xcodegen` (`brew install xcodegen`).

```bash
git clone <repo-url> && cd vokab
make install     # build, copy to /Applications, launch
```

A locally built app is not quarantined, so no `xattr` step is needed.

## First run

vokab lives in the menubar (no Dock icon). To set up capture:

1. Open **Settings** from the menubar popover.
2. Set a **global hotkey** and enable it.
3. Grant **Accessibility** when prompted (System Settings → Privacy & Security → Accessibility). The hotkey reads your selection by synthesizing ⌘C, which needs this permission.
4. If `agy` is not at `~/.local/bin/agy`, set its path in Settings.

To capture: select text in any app and press your hotkey. vokab looks it up and saves it. Review due cards from the menubar popover.

## Upgrading

Download the new DMG and replace the app, then re-run the `xattr` command. Because the app is ad-hoc signed, each build has a different signature, so macOS treats it as a new app — you must **re-grant Accessibility** (System Settings → Privacy & Security → Accessibility: remove the old entry, add the new one).

## How it works

```
select text → hotkey → agy → JSON → SQLite (GRDB) → SM-2 review
```

- **`VokabKit`** (Swift package) — all logic: agy wrapper, card models, GRDB storage, SM-2, capture orchestration. Unit-tested offline.
- **App target** — SwiftUI UI, menubar agent, notifications. A thin layer over `VokabKit`.

## Building & tests

```bash
make build       # compile
make run         # build + launch
make release     # Release build → ad-hoc sign → dist/vokab-<version>.dmg
make help        # list all targets
```

Engine/logic tests (no `agy` needed):

```bash
swift test
```

Real-`agy` contract tests (require `agy` installed & logged in):

```bash
VOKAB_AGY_INTEGRATION=1 swift test
```

## Code signing

The project uses ad-hoc signing (`CODE_SIGN_IDENTITY = "-"`, no team) so anyone can clone and build without an Apple Developer account. Released DMGs are ad-hoc signed too, not notarized — hence the `xattr` step on download. To sign with your own identity, put your settings in a `*.local.xcconfig` (gitignored); never commit a team ID.

## License

MIT — see [LICENSE](LICENSE).

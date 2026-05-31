# ShellCraft

macOS app for managing shell configuration through a native GUI.

## Build & Run

```bash
xcodegen generate                  # Regenerate .xcodeproj from project.yml
xcodebuild -project ShellCraft.xcodeproj -scheme ShellCraft -configuration Debug \
  -derivedDataPath ~/Library/Developer/Xcode/DerivedData/ShellCraft-btghkkwhgqrpkvcxxrffbfehbzie build
open ~/Library/Developer/Xcode/DerivedData/ShellCraft-btghkkwhgqrpkvcxxrffbfehbzie/Build/Products/Debug/ShellCraft.app
```

Always launch the app after a successful build.

## Release Process

Automated via `release.sh`. The script handles version bump, build, code signing, notarization, packaging, git tag, and GitHub release creation.

### Usage
```bash
./release.sh                    # Interactive: prompts for version bump type
./release.sh --bump patch       # Non-interactive: auto-selects bump type (patch/minor/major)
./release.sh --dry-run          # Preview version changes without executing
./release.sh --skip-notarize    # Skip notarization (for testing builds)
```

### Prerequisites (one-time setup)
1. **Developer ID signing** — handled automatically via Xcode managed signing. If export fails, install a Developer ID Application certificate from [developer.apple.com](https://developer.apple.com/account/resources/certificates/list)
2. **Notarytool keychain profile** — run:
   ```bash
   xcrun notarytool store-credentials "ShellCraft" --apple-id YOUR_APPLE_ID --team-id N9DRSTM2U6
   ```
3. **GitHub CLI** — `brew install gh` and authenticate with `gh auth login`

### What the Script Does
1. Preflight checks (tools, certificates, clean git, main branch)
2. Prompts for version bump (patch/minor/major/custom) and increments build number
3. Updates `project.yml`, regenerates `.xcodeproj` (with icon fix)
4. Archives and exports with Developer ID signing
5. Submits to Apple notary service and staples the ticket
6. Packages as `Releases/ShellCraft-{version}.zip`
7. Commits version bump, tags `v{version}`, pushes
8. Creates GitHub release with auto-generated notes

### Output
- `Releases/ShellCraft-{version}.zip` — notarized release artifact (gitignored)
- Build artifacts in `build/` are cleaned up automatically

## Project Setup

- **XcodeGen**: `project.yml` is the source of truth. Never edit `.xcodeproj` manually — run `xcodegen generate` after adding/removing files.
- **Deployment target**: macOS 26.0 (Tahoe)
- **Swift 6** with strict concurrency (`SWIFT_STRICT_CONCURRENCY: complete`)
- **No SPM dependencies** — pure SwiftUI + AppKit

## XcodeGen Gotchas

### Icon Composer files (`.icon`)

XcodeGen doesn't natively understand `.icon` bundles (Icon Composer format). Two issues arise:

1. **Folder expansion**: XcodeGen recurses into `ShellCraft.icon/` and adds `icon.json` / `Assets/` as individual files instead of treating it as an opaque folder reference.
2. **Wrong file type**: XcodeGen's `type: folder` produces `lastKnownFileType = folder`, but Xcode needs `folder.iconcomposer.icon` to recognize it as an app icon.

**Fix in `project.yml`**: Exclude from normal sources, add back as folder reference, and set the icon name:
```yaml
sources:
  - path: ShellCraft
    excludes:
      - "ShellCraft.icon"
  - path: ShellCraft/ShellCraft.icon
    type: folder
    buildPhase: resources
settings:
  base:
    ASSETCATALOG_COMPILER_APPICON_NAME: ShellCraft
```

**Post-generate fix** (required after every `xcodegen generate`):
```bash
sed -i '' 's|lastKnownFileType = folder; name = ShellCraft.icon; path = ShellCraft/ShellCraft.icon; sourceTree = SOURCE_ROOT;|lastKnownFileType = folder.iconcomposer.icon; path = ShellCraft.icon; sourceTree = "<group>";|' ShellCraft.xcodeproj/project.pbxproj
```

Without this sed fix, the icon file type is wrong and the app icon won't appear.

## Architecture

### Patterns

- **MVVM** with `@MainActor @Observable` ViewModels
- **`AppState`** — environment object for sidebar selection and unsaved-changes tracking per section
- **Round-trip safe writes** — raw `.zshrc` lines are kept in memory; only targeted lines are modified via `ShellConfigWriter.Modification`
- **`ProcessService`** wraps shell commands via `/bin/zsh -c`
- **`FileIOService`** handles all file reads/writes with atomic writes and automatic backup

### Directory Layout

```
ShellCraft/
├── App/               # ShellCraftApp, AppState
├── Models/            # Data models (ShellAlias, OhMyZshPlugin, etc.)
├── Services/          # Business logic (ShellConfigParser, OhMyZshService, etc.)
├── ViewModels/        # @MainActor @Observable VMs — one per sidebar section
├── Views/
│   ├── Sidebar/       # SidebarView, SidebarSection enum
│   ├── Shell/         # Aliases, Functions
│   ├── OhMyZsh/       # Oh My Zsh themes/plugins/settings
│   ├── Path/          # PATH manager
│   ├── Environment/   # Env vars
│   ├── Claude/        # Claude Code settings (tabbed)
│   ├── Git/           # Git config
│   ├── SSH/           # SSH config
│   ├── Secrets/       # Keychain secrets
│   ├── Tools/         # Custom tools
│   ├── Homebrew/      # Homebrew packages
│   └── Shared/        # Reusable: SaveBar, ImportExportToolbar, SearchableList, etc.
├── Extensions/        # String+Shell, URL+Home
├── Utilities/         # ShellLineParser, FileWatcher, PathValidator
└── Resources/         # Assets.xcassets
```

### Adding a New Sidebar Section

1. Add case to `SidebarSection` enum (`SidebarSection.swift`) — set `displayName`, `icon`, `group`
2. Add routing in `ContentView.detailView(for:)`
3. Create Model, Service, ViewModel, and View files following existing patterns
4. Run `xcodegen generate` to pick up new files

### Key Conventions

- **SaveBar pattern**: All editable sections show a `SaveBar` at the bottom when `hasUnsavedChanges` is true. Changes are only written on explicit Save; Discard reverts to the loaded state.
- **Import/Export**: Each section implements `exportData()`, `previewImport(_:)`, `applyImport(_:)`. Export uses `ImportExportService.export()` with `NSSavePanel`. Import shows an `ImportConfirmationSheet` preview before applying.
- **Dirty tracking**: ViewModels compare current state against a saved snapshot (e.g., `savedSnapshot`, `originalTheme`, `originalEnabledPlugins`).
- **`ShellConfigWriter.Modification`**: All `.zshrc` writes go through `.updateLine`, `.insertAfter`, `.deleteLine`, or `.appendLine` — applied in reverse index order for safe multi-edit.
- **Tabbed sections** (Claude Code, Oh My Zsh): Use `TabView` with `.tabViewStyle(.grouped)` and a tab enum with `rawValue`/`icon` properties.

### String Extensions (`String+Shell.swift`)

- `.expandingTildeInPath` — expands `~` to home directory
- `.shellEscaped` — escapes special shell characters
- `.singleQuoted` / `.doubleQuoted` — wraps for shell safety
- `.abbreviatingWithTildeInPath` — replaces home dir with `~`
- `.trimmed` — trims whitespace/newlines

## Clawpatch Code Review

This repo uses [Clawpatch](https://clawpatch.ai) for local automated code review. Keep `.clawpatch/` ignored; it is generated runtime state containing features, findings, reports, runs, and patch attempts.

Standard workflow:

```bash
clawpatch doctor
clawpatch init          # first time only
clawpatch map
clawpatch review --limit 10
clawpatch report --output .clawpatch/reports/summary.md
clawpatch show --finding <id>
clawpatch fix --finding <id>
clawpatch revalidate --finding <id>
```

If this repo needs hand-authored feature coverage, keep those curated definitions in `tools/clawpatch/features/` and sync/copy them into `.clawpatch/features/` before review. Do not commit `.clawpatch/` generated state.


<!-- BEGIN CLAUDE MEMORY IMPORT: -Users-omarshahine-GitHub-ShellCraft -->
## Imported Claude Project Memory

Durable memory promoted from `~/.claude/projects/-Users-omarshahine-GitHub-ShellCraft/memory` during the AGENTS.md migration. Keep this section current when project-specific operating knowledge changes.

### memory/MEMORY.md

# ShellCraft Project Memory

## User Preferences
- **Always launch the app after building** — run `open` on the built `.app` from DerivedData after every successful `xcodebuild`

## Project Details
- macOS 26.0 (Tahoe) deployment target, Swift 6 strict concurrency
- Uses XcodeGen (`project.yml`) to generate `ShellCraft.xcodeproj`
- Build output: `~/Library/Developer/Xcode/DerivedData/ShellCraft-btghkkwhgqrpkvcxxrffbfehbzie/Build/Products/Debug/ShellCraft.app`
- Uses `@MainActor @Observable` pattern for ViewModels
- `ProcessService` wraps shell commands via `/bin/zsh -c`
- `String+Shell.swift` provides `.trimmed`, `.singleQuoted`, `.shellEscaped` extensions

## Import/Export Feature — In Progress
- See [import-export-progress.md](import-export-progress.md) for detailed status

### memory/import-export-progress.md

# Import/Export Feature — COMPLETE

## Foundation Files — DONE
- `ShellCraft/Services/ImportExportService.swift` — NSSavePanel/NSOpenPanel wrappers, `ExportFileType`, `ImportPreview: Identifiable`, `shellHeader(section:)`, `importFileURL()`
- `ShellCraft/Views/Shared/ImportExportToolbar.swift` — Reusable `Menu` with Export/Import buttons
- `ShellCraft/Views/Shared/ImportConfirmationSheet.swift` — Shared confirmation sheet showing preview

## All 10 Sections — DONE

| Section | ViewModel Methods | View Integration | Format | Import Style |
|---------|------------------|------------------|--------|-------------|
| Aliases | `exportData()`, `previewImport()`, `applyImport()` | Toolbar + sheet + helpers | `.sh` | Merge by name |
| Functions | `exportData()`, `previewImport()`, `applyImport()` | Toolbar + sheet + helpers | `.sh` | Merge by name |
| PATH | `exportData()`, `previewImport()`, `applyImport()` | Toolbar + sheet + helpers | `.sh` | Merge (skip dupes) |
| Env Vars | `exportData()`, `previewImport()`, `applyImport()` | Toolbar + sheet + helpers | `.sh` | Merge by key |
| Git | `exportData()`, `previewImport()`, `applyImport()` | Toolbar + sheet + helpers | `.gitconfig` | Replace |
| Claude | `exportData()`, `previewImport()`, `applyImport()` | Toolbar + sheet + helpers | `.json` | Replace |
| SSH | `exportData()`, `previewImport()`, `applyImport()` | Toolbar + sheet + helpers (hosts only) | `.txt` | Merge by Host |
| Secrets | `exportData()`, `previewImport()`, `applyImport()` (async) | Toolbar + sheet + helpers | `.json` | Merge by serviceName |
| Custom Tools | `exportData()`, `previewImport()`, `applyImport()` | Toolbar + sheet + helpers | `.json` | Merge by name |
| Homebrew | `exportData()`, `importBrewfile(at:)` | Toolbar + confirmation alert | `Brewfile` | brew bundle direct |

## Build Status
- Builds successfully with `xcodegen generate && xcodebuild`
- App launches and runs

---

## Oh My Zsh Section — FUTURE (Not Implemented)
A planned new sidebar section for managing Oh My Zsh themes, plugins, and settings.
See plan file for full details.

<!-- END CLAUDE MEMORY IMPORT: -Users-omarshahine-GitHub-ShellCraft -->

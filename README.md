# ShellCraft

A native macOS app for managing your shell configuration through a GUI. No more hunting through dotfiles — edit your aliases, PATH, SSH keys, Git config, and more from a single window.

![macOS 26.0+](https://img.shields.io/badge/macOS-26.0+-blue) ![Swift 6](https://img.shields.io/badge/Swift-6-orange) ![No Dependencies](https://img.shields.io/badge/dependencies-none-green)

## What It Does

ShellCraft reads your actual config files (`.zshrc`, `.gitconfig`, SSH configs, etc.), lets you edit them through a structured UI, and writes changes back safely — preserving comments, formatting, and anything it doesn't understand.

### Sections

| Section | What It Manages |
|---------|----------------|
| **Aliases** | Shell aliases from `.zshrc` |
| **Functions** | Shell functions from `.zshrc` |
| **PATH** | `$PATH` entries with drag-to-reorder |
| **Environment** | Environment variables from `.zshrc` |
| **Oh My Zsh** | Themes, plugins, and settings |
| **Git** | `.gitconfig` and global `.gitignore` |
| **SSH** | SSH config hosts, key generation, key management |
| **Secrets** | macOS Keychain secrets with encrypted export/import |
| **Homebrew** | Installed packages and casks |
| **Claude Code** | `settings.json`, permissions, hooks, plugins, MCP servers |
| **Tools** | Custom CLI tools |

Every section supports import/export and shows a save bar when you have unsaved changes.

## Getting Started

### Prerequisites

- macOS 26.0 (Tahoe) or later
- Xcode 17+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

### Build & Run

```bash
xcodegen generate
xcodebuild -project ShellCraft.xcodeproj -scheme ShellCraft -configuration Debug \
  -derivedDataPath ~/Library/Developer/Xcode/DerivedData/ShellCraft build
open ~/Library/Developer/Xcode/DerivedData/ShellCraft/Build/Products/Debug/ShellCraft.app
```

**Important:** After running `xcodegen generate`, apply the icon fix:

```bash
sed -i '' 's|lastKnownFileType = folder; name = ShellCraft.icon; path = ShellCraft/ShellCraft.icon; sourceTree = SOURCE_ROOT;|lastKnownFileType = folder.iconcomposer.icon; path = ShellCraft.icon; sourceTree = "<group>";|' ShellCraft.xcodeproj/project.pbxproj
```

XcodeGen doesn't understand `.icon` bundles (Icon Composer format), so this sed command fixes the file type in the generated project.

## Architecture

- **MVVM** with `@MainActor @Observable` ViewModels
- **Pure SwiftUI + AppKit** — no third-party dependencies
- **Round-trip safe writes** — config files are parsed into memory; only targeted lines are modified on save
- **XcodeGen** — `project.yml` is the source of truth, never edit `.xcodeproj` directly

See [CLAUDE.md](CLAUDE.md) for detailed architecture docs, conventions, and contributor instructions.

## Key Design Decisions

**Why not just edit the files directly?** You can, and ShellCraft will pick up external changes. But a GUI makes it easier to discover what's configured, avoid syntax errors, and manage things like SSH keys and Keychain secrets that are awkward from the terminal.

**Why no SPM dependencies?** Everything ShellCraft needs is in the platform SDKs. No dependency management, no version conflicts, no supply chain risk.

**Why XcodeGen?** The `.xcodeproj` format is hostile to version control. `project.yml` is human-readable and merge-friendly.

## License

Private project. Not currently open source.

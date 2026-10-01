# Frequent Finder — Design

Date: 2026-10-01
Status: approved in chat, pending spec review

## Goal

A macOS menu bar utility that lists the user's active projects and gives
one-click access to each project's folder, terminal, git status, key files
and URLs. Projects can be managed from a Settings window or from a CLI.

Single user, own Macs, not distributed (yet). Replaces the abandoned
Python/Qt attempt in `old-python/`, which is not reused.

## Decisions

| Topic | Decision |
|---|---|
| Platform | macOS only, Swift + SwiftUI, `MenuBarExtra` with `.window` style |
| Build | Swift Package (no Xcode project); `scripts/make-app.sh` wraps the app into `FrequentFinder.app` |
| Distribution later | Either wrap the package in an Xcode app project, or sign/notarize the script-built bundle with `codesign` + `notarytool` |
| Storage | One JSON file: `~/.config/frequent-finder/projects.json` |
| "SDK" | The `ff` CLI plus the documented JSON file. No Swift library for outside use (yet) |
| Key files | Exact paths, picked with a multi-select file dialog rooted at the project folder; stored relative to the project root |
| Terminal | One global choice: Terminal or iTerm |
| Active flag | None. Every project in the file is shown |
| Dependencies | None beyond the Swift toolchain and system frameworks |

## Package layout

```
Package.swift
Sources/
  FFCore/     Project model, config load/save, git status, open Finder/terminal, CLI command logic
  FFApp/      Menu bar app (SwiftUI)
  ff/         CLI entry point (thin wrapper over FFCore)
Tests/FFCoreTests/
scripts/make-app.sh
```

## Data model

```json
{
  "terminal": "terminal",
  "projects": [
    {
      "name": "Frequent Finder",
      "path": "/Users/me/code/frequent-finder",
      "keyFiles": ["README.md", "docs/superpowers/specs/2026-10-01-frequent-finder-design.md"],
      "urls": [{ "url": "https://github.com/me/frequent-finder", "label": "GitHub" }]
    }
  ]
}
```

- `terminal`: `"terminal"` or `"iterm"`. Default `"terminal"`.
- `name`: unique, compared case-insensitively. Used by the CLI to pick a project.
- `path`: absolute path. `~` is expanded on input, stored expanded.
- `keyFiles`: files or folders. Stored relative to `path` when inside it, else as an absolute path.
- `repos`: git repositories shown with their own status; stored like `keyFiles`. A repo is a folder
  containing `.git`. "Find Repositories" / `ff repo find` adds all repos up to 3 levels below the
  project (skipping hidden folders and folders inside a found repo). The menu sums up the project
  folder and its repos: dirty if any is dirty, ↑/↓ added up.
- `urls[].label`: optional. If missing, the URL itself is shown.
- Project order = array order.
- Missing file on first run = empty config. The directory is created on first save.

### Saving

- Every save writes a temp file in the same directory and atomically replaces
  the original (`Data.write(options: .atomic)`).
- If the file exists but cannot be parsed, load fails with an error. Neither the
  app nor the CLI overwrites a file it could not parse.

## Menu bar app

- Runs as an accessory app (no Dock icon): `LSUIElement` in the bundle's `Info.plist`.
- Watches `projects.json` for changes (file system event source on the directory,
  so atomic replaces are seen) and reloads.

### Menu bar panel

- Menu bar icon: SF Symbol (e.g. `folder.badge.gearshape`).
- Click opens an attached panel listing projects by name.
- Each row has a git dot: green = clean, orange = dirty, grey = not a git repo.
- Missing project folder: row greyed out with "folder not found".
- Click a row: opens (or brings to front) that project's window.
- Bottom bar: gear icon (opens Settings) and Quit button.
- Parse error: panel shows the error message instead of the list.

### Project window

One window per project (`WindowGroup(for:)` keyed by project name).

- Header: project name, path.
- Git line: branch name + dot; dirty also shows the count of changed files.
  Refreshed when the window opens, when it becomes key, and via a refresh button.
  Not a git repo: "Not a git repository".
- Buttons:
  - Open in Finder (`NSWorkspace.open` on the folder).
  - Open Terminal: `open -b com.apple.Terminal <path>` or `open -b com.googlecode.iterm2 <path>`
    per setting. Bundle IDs, not app names, so it works wherever the app is installed
    (iTerm is in `~/Applications` on this Mac). If the launch fails, show the error.
- Key files section (hidden if empty): click opens with the default app;
  a reveal button shows it in Finder. Missing files are greyed out.
- URLs section (hidden if empty): click opens in the default browser.

### Settings window

- Terminal picker: Terminal / iTerm.
- Open at login toggle (`SMAppService.mainApp`).
- Project list (left): add, remove, move up/down.
- Project detail (right):
  - Name (text field; duplicate names rejected with an inline message).
  - Path (text + "Choose…" folder picker).
  - Key files: list with remove; "Add Files or Folders…" opens `NSOpenPanel` at the project
    folder with multiple selection of files and folders, from any location.
  - URLs: list of label + URL with add, edit, remove.
- Every change saves immediately.

## Git status

Run `git -C <path> status --porcelain=v2 --branch` via `Process`.

- Branch: from the `# branch.head` line. `(detached)` shown as "detached".
- Dirty: any non-`#` line. Count = number of such lines.
- Non-zero exit (not a repo, or git missing): "not a git repository" state.
- Runs off the main thread.

## CLI (`ff`)

```
ff list [--json]
ff add <path> [--name "Name"]        name defaults to the folder name
ff remove <name>
ff rename <name> <new-name>
ff set-path <name> <path>
ff file add <name> <file>...         file may be absolute or relative to the current dir
ff file remove <name> <file>...
ff url add <name> <url> [--label "Label"]
ff url remove <name> <url>
ff terminal [terminal|iterm]         no argument = print current value
ff help
```

- Arguments parsed by hand (no ArgumentParser).
- Errors go to stderr with a clear message and exit code 1. Usage errors exit 2.
- `add` rejects a path that is not an existing directory and a duplicate name.
- `file add` rejects files that do not exist; stores the path relative to the project
  when inside it, else absolute; ignores duplicates.
- `url add` rejects strings that are not valid `http`/`https`/`file` URLs.
- Command logic lives in FFCore as functions over the config value, so it is
  testable without spawning a process.

## Build and install

`scripts/make-app.sh`:

1. `swift build -c release`
2. Create `build/FrequentFinder.app/Contents/{MacOS,Info.plist}` with `LSUIElement=true`.
3. Copy the `FFApp` binary in; ad-hoc sign (`codesign -s -`) so `SMAppService` works.
4. Copy `ff` to `~/.local/bin/ff`.

The user moves `FrequentFinder.app` to `/Applications` (or the script does it with a flag).

## Testing

Automated (`swift test`, FFCore only):

- Config JSON round trip; missing file = empty config; broken file = error, not overwritten.
- Each CLI command's logic, including error cases (duplicate name, unknown name,
  file outside project, bad URL).
- Git status parsing against a real temporary git repo: clean, dirty with count,
  branch name, not-a-repo.

Manual:

- Build the app, run it, check panel, project window, Settings, file picker,
  terminal launch (both Terminal and iTerm), live reload after a CLI change.

## Out of scope (for now)

- Per-project terminal choice.
- Glob patterns for key files.
- Hiding projects without deleting them.
- A Swift library for outside callers.
- App Store or notarized distribution.

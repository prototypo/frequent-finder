# frequent-finder

A macOS menu bar utility to keep track of current projects and their files.

- Click the menu bar icon to see your projects, each with a git status symbol
  (✓ clean, ✎ dirty, dashed circle = not a git repo), plus ↑N commits to push and
  ↓N to pull (as of the last `git fetch`).
- Click a project to open its window: open the folder in Finder, open Terminal or
  iTerm there, see the branch, open key files and links.
- A project can list git repositories (for a folder holding many repos). Each shows its own
  status; the menu sums them up. Settings → Find Repositories adds all repos up to 3 levels down.
- Settings… (⌘,) edits projects, the terminal choice, Show in menu bar, and Open at login.
  If you hide the menu bar icon, open the app again from Finder or Spotlight to bring it back.
- The `ff` command does the same from the command line.

## Build and install

Needs macOS 15 or later and Xcode (or the Swift toolchain).

```bash
scripts/make-app.sh            # builds build/FrequentFinder.app and installs ~/.local/bin/ff
scripts/make-app.sh --install  # also copies the app to /Applications
```

Make sure `~/.local/bin` is on your `PATH`.

## Command line

```
ff list [--json]
ff add <path> [--name "Name"]
ff remove <name>
ff rename <name> <new-name>
ff set-path <name> <path>
ff file add <name> <file>...
ff file remove <name> <file>...
ff repo add <name> <path>...
ff repo remove <name> <path>...
ff repo find <name>
ff url add <name> <url> [--label "Label"]
ff url remove <name> <url>
ff terminal [terminal|iterm]
```

Project names are not case-sensitive. Errors exit with code 1, usage errors with code 2.

## Config file

`~/.config/frequent-finder/projects.json` (set `FF_CONFIG` to use another file).
The app reloads it when it changes.

```json
{
  "projects" : [
    {
      "keyFiles" : [ "README.md" ],
      "name" : "Frequent Finder",
      "path" : "/Users/me/code/frequent-finder",
      "repos" : [ ],
      "urls" : [ { "label" : "GitHub", "url" : "https://github.com/me/frequent-finder" } ]
    }
  ],
  "terminal" : "iterm"
}
```

`keyFiles` are files or folders: relative to `path` when inside the project, else absolute (shown as `(external)/<name>`). `repos` are stored the same way. `label` is optional. `terminal` is `terminal` or `iterm`.

## Development

```bash
swift test
swift scripts/make-icon.swift   # redraws Resources/AppIcon.icns
```

The old Python/Qt attempt is in `old-python/` and is not used.

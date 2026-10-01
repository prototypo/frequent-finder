# frequent-finder

A macOS menu bar utility to keep track of current projects and their files.

- Click the menu bar icon to see your projects, each with a git status dot
  (green = clean, orange = dirty, grey = not a git repo).
- Click a project to open its window: open the folder in Finder, open Terminal or
  iTerm there, see the branch, open key files and links.
- Settings (gear icon) edits projects, the terminal choice, and Open at login.
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
      "urls" : [ { "label" : "GitHub", "url" : "https://github.com/me/frequent-finder" } ]
    }
  ],
  "terminal" : "iterm"
}
```

`keyFiles` are relative to `path`. `label` is optional. `terminal` is `terminal` or `iterm`.

## Development

```bash
swift test
```

The old Python/Qt attempt is in `old-python/` and is not used.

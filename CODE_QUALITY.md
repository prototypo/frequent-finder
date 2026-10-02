# Code Quality Report

Generated: 2026-10-02 by quality-report v0.4.1

## Summary

- Languages analyzed: Swift (detected-but-unsupported: no reference file; every count below is estimated)
- Not analyzed: Python in `old-python/` (abandoned first attempt, not built) and `venv/` (third-party packages)
- Files analyzed: 16 (`Sources/`, `scripts/`, `Package.swift`; 1,583 lines). Tests (`Tests/`) are excluded from the metrics but were searched for dead-code references.
- Tools used:
  - swift_metrics.py — ad-hoc estimating script (comment- and string-stripped brace matching; complexity = 1 + `if`/`guard`/`for`/`while`/`case`/`catch`/`&&`/`||`/`??`/ternary)
  - grep — error-handling smells
- Tools missing: no Swift reference tool (e.g. SwiftLint, Lizard) — all metrics estimated by script plus reading code
- Findings: 0 open

Swift error-handling smell, defined for this run: `try!`, force unwrap `!`, and `try?` that silently drops an error that matters. `try?` used as a deliberate "absent = nil" lookup is not counted (`AppModel.swift:54`, `Git.swift:66`, `make-icon.swift:31`).

SwiftUI note: a view's `body` nests closures by design (`Form { Section { HStack { … } } }`), so brace-based nesting depth reads higher for views than for plain functions.

## Metrics

| Metric | Threshold | Status | Compliance | Source |
|---|---|---|---|---|
| Cyclomatic complexity | > 10 | 🟢 100% pass | 🟢 109 · 🟡 1 · 🔴 0 | estimated |
| Function length | > 50 lines | 🟢 100% pass | 🟢 110 · 🟡 0 · 🔴 0 | estimated |
| Nesting depth | > 4 levels | 🟢 100% pass | 🟢 104 · 🟡 6 · 🔴 0 | estimated |
| Argument count | > 5 | 🟢 100% pass | 🟢 106 · 🟡 4 · 🔴 0 | estimated |
| File size | > 500 lines | 🟢 100% pass | 🟢 16 · 🟡 0 · 🔴 0 | estimated |
| Dead code | any | 🟢 100% used | 🟢 100% (110/110) | estimated |
| Error-handling smells | `try!`, force unwrap, error-dropping `try?` | 🟢 0.0 / 1k lines | 🟢 0.0 / 1k lines (0 in 1,583) | estimated |
| Code duplication | ≥ 5 similar lines | 🟢 0.8% duplicated | 🟢 0.8% (estimated) | estimated |
| Reusability | shared function missing | 🟢 0.8% duplicated | 🟢 0 groups | estimated |
| Comment quality | WHAT, not HOW (functions > 10 lines) | 🟢 100% pass | 🟢 28 · 🔴 0 | estimated |

Comment counts are parsed from every function in the code base; comment
*quality* and the other judgment metrics (reusability, suppressed
problems) are judged on a sample only — the files with findings, plus up
to 10 of the largest remaining source files. "estimated" in the Source
column marks a count made by reading code instead of by a tool.

Comment-quality compliance covers the 28 functions longer than 10 lines. A SwiftUI `body` is credited with its view type's `///` comment, since that comment says what the view shows. No suppression markers (`// swiftlint:disable` etc.) were found.

Dead code: four functions are referenced only at their declaration — `makeNSView`, `updateNSView` (`NSViewRepresentable`), `applicationShouldTerminate`, `applicationShouldHandleReopen` (`NSApplicationDelegate`). AppKit and SwiftUI call these, so they are used.

Duplication: the closest remaining pair is `ProjectEditor.keyFileRow` and `repoRow` (SettingsView.swift), about 5 similar lines (name, path tooltip, spacer, remove button). They differ in the icon and the remove call; one shared helper would need a closure parameter and save little, so it is not a finding.

## Distribution

| Metric | Compliance | Worst | Median | Std dev |
|---|---|---|---|---|
| Cyclomatic complexity | 100% (110/110) | 10 | 2 | 1.7 |
| Function length | 100% (110/110) | 41 | 7 | 7.8 |
| Nesting depth | 100% (110/110) | 4 | 1 | 1.1 |
| Argument count | 100% (110/110) | 5 | 1 | 1.3 |
| File size | 100% (16/16) | 329 | 82.5 | 81.3 |

### Progress since the previous report (same day, before Q1–Q13)

| | before | after |
|---|---|---|
| functions | 91 | 110 |
| lines | 1,482 | 1,583 |
| complexity compliance | 98.9% (worst 27, sd 3.2) | 100% (worst 10, sd 1.7) |
| length compliance | 96.7% (worst 87, sd 15.1) | 100% (worst 41, sd 7.8) |
| nesting compliance | 95.6% (worst 6, sd 1.3) | 100% (worst 4, sd 1.1) |
| comment quality | 63% (12/19) | 100% (28/28) |
| error smells | 4.0 / 1k lines | 0.0 / 1k lines |
| duplication groups | 2 | 0 |

Functions rose by 19 and lines by 101 because the fixes split large functions into named helpers and views. Every ratio improved and every worst value and standard deviation fell.

File size is the one measure that rose (worst 288 → 329, sd 72.4 → 81.3): `SettingsView.swift` grew as `body` was split into named sections. It is still well under the 500-line limit.

### Counts lie when the denominator moves

Fixing these findings CHANGES THE DENOMINATOR, almost always upward:
extracting a helper adds a function, splitting a module adds a file. So a
raw count of violations can rise while the code base genuinely improves,
and a reader who watches only the count concludes the work made things
worse.

When reporting progress against this run: lead with the compliance ratio,
quote the worst value and the standard deviation, and if a count rose, say
whether the denominator rose too.

## Findings (worst first)

None. Every metric is within its threshold.

## Marginal (🟡) — close to the limit, no action required

- Cyclomatic complexity 10 (limit 10) — Sources/FFCore/CLI.swift:27 `CLI.run`
- Nesting depth 4 (limit 4) — Sources/FFCore/Git.swift:60 `Git.findRepositories`
- Nesting depth 4 (limit 4) — Sources/FFApp/AllProjectsView.swift:13 `AllProjectsView.body`
- Nesting depth 4 (limit 4) — Sources/FFApp/SettingsView.swift:51 `SettingsView.generalSettings`
- Nesting depth 4 (limit 4) — Sources/FFApp/SettingsView.swift:74 `SettingsView.projectList`
- Nesting depth 4 (limit 4) — Sources/FFApp/ProjectWindow.swift:19 `ProjectWindow.folderSection`
- Nesting depth 4 (limit 4) — Sources/FFApp/ProjectWindow.swift:41 `ProjectWindow.details`
- Argument count 5 (limit 5) — Sources/FFCore/Commands.swift:129 `Config.addItems`
- Argument count 5 (limit 5) — Sources/FFCore/Config.swift:45 `Project.init`
- Argument count 5 (limit 5) — Sources/FFCore/CLI.swift:67 `CLI.runProject`
- Argument count 5 (limit 5) — Sources/FFApp/SettingsView.swift:310 `choosePaths`

## Top recommendations

1. Nothing needs fixing now.
2. When adding a new CLI command, give it its own `run…` helper; `CLI.run` is at the complexity limit (10), so one more inline case would push it over.
3. If `SettingsView.swift` keeps growing towards 500 lines, move `ProjectEditor` into its own file.

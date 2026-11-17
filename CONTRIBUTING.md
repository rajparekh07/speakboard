# Contributing

This is how to work in this repo. The binding rules are in [AGENTS.md](AGENTS.md). Read that first.

## Run the checks

You need Docker, make, bash, grep and git. You do not need Swift: it runs inside Docker.

```sh
make check
```

`make check` runs these steps in order, and stops at the first failure:

1. **Core guard.** It first runs its own self-test, then checks that `Sources/SpeakboardCore` never mentions `FoundationNetworking` or any `URLSession` name. It follows symbolic links, because SwiftPM compiles a linked file into the core.
2. **Docker ready.** It first runs the self-test of its stale containerd pid check, which needs no daemon. It starts `dockerd` if it is not running, and pulls the Swift image if it is missing.
3. **Core dependency guard.** It first runs its own self-test, then checks that the `SpeakboardCore` target in `Package.swift` is a regular target, declares no dependencies and sets no `path`, `sources`, plugins or build settings of any kind (`swiftSettings`, `cSettings`, `cxxSettings`, `linkerSettings`: so no unsafe flags, defines or language mode), that the package sets no `swiftLanguageModes` and its tools version is 6.x (below 6.0 the core would build as Swift 5, and a later major version may default to a later mode than the imports guard reads), and that the `SpeakboardCore` product holds only that target. Those are ways to compile code into the core, or ship code beside it, from outside the folder the core guard reads, or to build the core in a language mode other than the Swift 6 the imports guard reads it in. It does not close every way: it reads only those keys of the package, the target and the product. It reads the package as SwiftPM sees it (`swift package dump-package`), inside Docker.
4. **Core imports guard.** It first runs its own self-test. Then it fails if any Swift file under `Sources/SpeakboardCore` contains conditional compilation (`#if`, `#elseif`, `#else`, `#endif`), naming the file and line. The compiler reports imports only in code it compiles, and which branches it compiles depends on the platform, the target and the build's defines (`swift build` adds `DEBUG` and `SWIFT_PACKAGE`), so the core has no branches at all. This step reads the text, so an `#if` in a comment or a string fails too, on purpose. Apple-only code goes under `Apple/`. Then it asks the compiler which modules each file imports (`swift-frontend -emit-imported-modules`, inside Docker) and fails, naming the file and the module, if any is not `Foundation`. Reading the compiler's answer rather than the text means every spelling of an import counts, and with no conditional compilation the compiler sees every import. It reads every file as Swift 6, which step 3 makes the only mode the core builds in. It fails closed: a failing `find`, a missing frontend, a non-zero exit (a syntax error, or a toolchain that drops the flag) or no output file fails it.
5. **Keyboard extension guard.** It first runs its own self-test. Then, for `Apple/Keyboard` and `Apple/KeyboardKit` (the code linked into the extension), it fails on any file that is not a Swift file (an `Info.plist` aside), on conditional compilation (for the core's reason: the compiler reports imports only in branches it compiles), and on any import of a module outside an allowlist: Foundation, UIKit, QuartzCore, OSLog, SpeakboardCore and KeyboardKit, each justified in `scripts/extension-guard.sh`. It reads the imports with the compiler (`swift-frontend -emit-imported-modules`, inside Docker), so every spelling counts. As a second net, not a proof, it fails on networking names in the text (`URLSession` and its relatives, Network and CFNetwork types, Foundation streams, `contentsOf:`, BSD socket calls). On macOS CI (rung 2) the guard also checks that `project.yml` builds the extension and KeyboardKit exactly as the extension guard expects (their whole target entries: sources, dependencies, settings, and no other key, such as a build tool plugin or a script phase), with only known project-wide settings and the core from this repo, and that the built extension's binaries load no SwiftUI and no networking framework (`otool -L`). What none of this sees: networking through APIs the allowlist already lets in. `URLSession` reached without a new import, `Data(contentsOf:)` with a URL, `Stream` and BSD sockets live in Foundation and libSystem, so they add no import and no linked library; only the text net might catch them. The manifesto's full privacy gate is its own ticket, KEY-11 ("Privacy gate: no networking code in the keyboard extension").
6. **Design tokens.** It checks that the pinned token export in `DesignTokens/` has the SHA-256 that `DesignTokens/tokens.pin` records, then runs the generator and fails if `Sources/SpeakboardCore/Layout/GeneratedMetrics.swift` differs from what it makes. See "Design tokens" below.
7. **Build.** `swift build`
8. **Tests.** `swift test`
9. **Format check.** `swift format lint --strict` on `Package.swift`, `Sources`, `Tests`, `scripts` and `Apple`. swift-format reads syntax only, so the Apple code is linted in the Linux image too, without UIKit.

It ends with `make check: OK`.

The Swift image is pinned to `swift:6.4.2-resolute` (Swift 6.4.2 on Ubuntu 26.04) in the `Makefile`. To change the Swift version, change `SWIFT_TAG` there, in its own commit.

The image is pinned by tag, not by digest. A tag can be re-pushed to point at a different image, and official images are rebuilt from time to time. On 15 Nov 2026, `swift:6.4.2-resolute` was the image with ID and digest `sha256:0384f00cf80f81064a907c249a0ad56a1648906f65075a95b1827e88de666e21`. Whether to pin by digest is the owner's call.

### In a fresh agent container

`make check` works in a fresh agent container with nothing set up. Expect two things on the first run:

* Nothing starts `dockerd`, so `make check` starts it in the background, as root. Its log is `/tmp/dockerd.log`.
* If `docker info` fails after the container's worker restarted, and `/tmp/dockerd.log` says "containerd is still running" for a process that no longer exists before `dockerd` exits, a stale `/var/run/docker/containerd/containerd.pid` is the cause. `make check` removes it, and the sockets beside it, before it starts `dockerd`, but only when no `dockerd` is running and the pid's process does not exist.
* The image is about 1.3 GB to download. Docker Hub rate-limits anonymous pulls, so `make check` pulls from `mirror.gcr.io/library/swift` first and from Docker Hub only if the mirror fails.

### On a Mac

`make check-native` runs the same steps as `make check` without Docker, with the active Swift toolchain:

```sh
make check-native
```

It needs Xcode, and Xcode's toolchain must be the active one. With only the Command Line Tools (their Swift is 6.3.3), the tests fail to compile with `no such module 'Testing'`. Check with `xcode-select -p`, which must print a path inside Xcode, and select Xcode with `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` if it does not. The scripts are written for the bash 3.2 at `/bin/bash` and the BSD tools macOS ships, so nothing needs installing from Homebrew.

It first checks that every tool the steps use is there (`swift`, `swift format`, the compiler frontend, a SHA-256 tool, and the rest) and fails, naming the tool, if one is not: a missing tool is a failure, never a skip. On macOS it finds the compiler frontend for the core imports guard with `xcrun -f swift-frontend`, and fails if the Command Line Tools are selected. It also fails unless the active Swift is the version the Makefile pins in `SWIFT_TAG` (6.4.2 today; Xcode 27.2 has it), because several of the guards' facts were checked with that version. After an Xcode update that brings another Swift, either select a toolchain with the pinned version, or change `SWIFT_TAG` in its own commit, which moves `make check` and `make check-native` together. Then it runs steps 1 and 3 to 9 above, each guard with its self-test, and ends with `make check-native: OK`. Step 2 is not part of it: it looks after the Docker daemon on a Linux host. (Its self-test says it is skipped on a host with no `/proc`, such as macOS.)

On macOS, `swift test` skips the allocation tests, with a message: there is no heap-allocation counter for macOS (KEY-8 found none that is sound with public API). Expect every test to pass except those 3, which skip. They run only on Linux (`make check`, or `make check-native` there).

The step targets take `NATIVE=1` to run one step on the host too: `guard-deps`, `guard-imports`, `guard-extension`, `metrics-check`, `metrics`, `build`, `test`, `format-check` and `format`, for example `make NATIVE=1 guard-imports` (`guard` always runs on the host). `make check` refuses `NATIVE=1`, whether it comes from the command line or the environment. The variables the steps read (`RUN`, `DOCKER_READY`, `SWIFT_TAG`, `CHECK_STEPS` and the rest) are declared `override`, and the repo is mounted by the shell's working directory, not make's `CURDIR`, so a value given for any of them on the command line, in the environment or through `MAKEFLAGS` is ignored. Make's own flags (`-i`, `-k`, `-o`, `-n`, `-t`), its own variables (`SHELL=`, `MAKE=`) and edits to the `Makefile` are not defended: with them, `make check: OK` can print for a check that did not run. CI, which runs the `Makefile` unmodified, is the authority for a green check. `make check-native` also works on Linux with Swift installed, but `make check` in Docker stays the check every ticket must pass.

### Other targets

| Target | What it does |
| -- | -- |
| `make check-native` | Every step but Docker ready, on the host, without Docker. See "On a Mac" |
| `make guard` | The core guard and its self-test only. Needs no Docker |
| `make guard-deps` | The core dependency guard and its self-test only |
| `make guard-imports` | The core imports guard and its self-test only |
| `make guard-extension` | The keyboard extension guard (sources) and its self-test only |
| `make metrics-check` | The design token step only |
| `make metrics` | Regenerates the metrics tables from the pinned token export |
| `make build` | `swift build` in Docker |
| `make test` | `swift test` in Docker |
| `make format-check` | The format check only |
| `make format` | Rewrites Swift files in place to match `.swift-format` |
| `make clean` | Removes `.build` |

## The build loop

Each ticket goes through this loop.

1. The orchestrator moves the ticket to In Progress and starts a builder.
2. The builder reads the ticket, `AGENTS.md` and the manifesto. It builds the ticket and nothing else.
3. The builder runs `make check`, commits, pushes, and returns a summary and a testing report.
4. A fresh reviewer reviews the pushed commits against the ticket. It checks the evidence itself. Its verdict is **approve**, **approve with changes** or **rework**. Each finding is a **blocker**, **should-fix** or **nit**.
5. If the verdict is not approve, the builder fixes every blocker and should-fix, or disputes it in writing with a reason the next reviewer can check. It answers every nit. It pushes the fixes on top.
6. A new reviewer reviews the new head. The loop ends when a round approves with no blocker or should-fix open. After 5 rounds, the orchestrator stops and asks the owner.
7. The orchestrator records each round on the Linear ticket. It moves the ticket to Done once the approved commits are on the working branch and their checks pass. Approved work reaches `main` through the ticket's pull request, which the orchestrator merges once the ticket is approved (its reading of the owner's standing rule of 16 Nov 2026; see "Where work lands" below).

A fresh fixer replaces the builder when the same finding survives two rounds, when the findings say the approach is wrong, or when the builder's context has degraded. The orchestrator asks the owner before round 5 if a dispute survives a second reviewer, or if round 3 repeats round 2's findings.

## Where work lands

There are two branches (ADR-0021, which replaced the one-branch rule of ADR-0013 on 16 Nov 2026):

* `feature/sharp-einstein-aydugs` is the working branch. Every ticket is built on it and pushed to it, one repo-changing ticket at a time, and reviewed there. Reviews are recorded on the Linear ticket.
* `main` holds work a fresh reviewer has approved. It reaches `main` through a pull request from the working branch. The owner's standing rule of 16 Nov 2026 is "merge PRs when done instead of large PRs" (recorded on ADR-0021). The orchestrator reads it so: one pull request per ticket, which may also hold a small follow-up ticket built and reviewed with it, opened by the orchestrator and merged by it once a fresh reviewer has approved the ticket. After a merge, the working branch continues from `main`. `main` is never red: nothing is merged unless the checks passed on the commit being merged.

A builder pushes only to the working branch. It never pushes to `main`, never creates a branch, and never opens or merges a pull request.

Push your commits, so that nothing is lost if the container is reclaimed. The reviewer reviews a named commit. If a ticket is rejected and cannot be rescued, the orchestrator reverts its commits.

## Commit messages

```
[KEY-n] Subject in the imperative, under about 70 characters

A short body that says why the change was made, not only what it does.
```

`KEY-n` is the ticket's Linear ID. Every commit of a ticket carries it, so the ticket is one commit range. Add any attribution lines your session asks for at the end.

## The four rungs

Every testing report names the rung that verified the work.

| Rung | Where | What it can prove | Status today |
| -- | -- | -- | -- |
| 1. Linux Swift | The agent's container, Swift in Docker | The core: build, unit tests, formatting | Working. This is `make check` |
| 2. macOS CI | GitHub Actions macOS runners | The Xcode project builds, simulator tests, screenshots | Working (KEY-8): `.github/workflows/macos.yml` on the `xcode-27` runner, Xcode 27.2, on every push. See "macOS CI" below |
| 3. The owner's Mac | Remote Control from the Claude desktop app | Interactive Xcode, the simulator, Instruments | Working: Xcode 27.2 and the iOS 27.2 simulator. `make check-native` runs the core's checks there (KEY-57), and the Xcode project builds and runs there as on macOS CI (KEY-8). The 3 heap-allocation tests skip on macOS: there is no macOS allocation counter, so they run only on Linux (`make check`, or `make check-native` there) |
| 4. A real iPhone | TestFlight | Latency, memory, battery, haptics, the app hop, the microphone. The only rung that proves a budget | No developer account or test iPhone yet |

Rung 1 also runs on GitHub. Every push to the working branch or to `main` runs `make check` on a GitHub-hosted Linux runner (`.github/workflows/linux.yml`), and each run uploads its log as the artifact `make-check-log`. Still run `make check` yourself before you push.

### macOS CI

Every push to the working branch or to `main` also runs `.github/workflows/macos.yml` on GitHub's `xcode-27` runner. It selects Xcode 27.2, whose Swift is the pinned 6.4.2 (the runner's default is 27.1), prints what the runner has (Xcode installs and their Swift, SDKs, simulator runtimes and devices), and then:

1. `make check-native`.
2. Installs XcodeGen from its release zip, checked against a pinned SHA-256, and generates the project. It fails if generating leaves any file git would see.
3. Builds the app and the keyboard extension for the iPhone 18 Pro simulator, iOS 27.2.
4. The extension guard's macOS-only checks: its `project` self-test, `scripts/extension-guard.sh project project.yml` (the project builds the extension and KeyboardKit exactly as the extension guard expects (their whole target entries: sources, dependencies, settings, and no other key, such as a build tool plugin or a script phase), with only known project-wide settings and the core from this repo) and `scripts/extension-guard.sh binary` on the built extension (no SwiftUI and no networking framework loaded).
5. The unit tests (`KeyboardKitTests`).
6. `scripts/sim-keyboard.sh`: a fresh simulator, a screenshot of the keyboard's view in the app's harness, then the keyboard extension enabled with Full Access and shown in the app's text field, with a second screenshot. It fails unless the extension itself logs that it ran with Full Access. How it enables the keyboard is in the script.

It uploads the screenshots and logs as the artifact `macos-screenshots-and-logs`. To run the same on a Mac:

```sh
xcodegen generate
xcodebuild -project Speakboard.xcodeproj -scheme Speakboard \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.2' -derivedDataPath .build/xcode test
scripts/sim-keyboard.sh .build/xcode/Build/Products/Debug-iphonesimulator/Speakboard.app \
  "iPhone 18 Pro" com.apple.CoreSimulator.SimRuntime.iOS-27-2 .build/screenshots
```

The bundle identifiers in `project.yml` are placeholders until the owner has an Apple Developer account. Simulator builds need no signing, and no team is set.

To read a run, read its job log with the GitHub job-log tool (`get_job_logs`). To find the job, list the branch's runs and match the head SHA, then list that run's jobs; for a red run, the job-log tool takes the run id with its failed-only option. The log holds the full `make check` output. You can list a run's artifacts, but you cannot download their contents from a session until the owner resolves KEY-54. Do not try, and do not ask the owner for a network change for it.

## Where code goes

```
Package.swift
Sources/SpeakboardCore/    the core: pure Swift, Foundation only, builds on Linux
  KeyboardLocale.swift     the locale type, shared by every area with data per locale
  Layout/                  key layouts, per-device metrics, hit-test geometry
  Typing/                  the key-event state machine
  Autocorrect/             touch model, lexicon, language model, suggestions
  Cleanup/                 transcript rules
  Session/                 the dictation session state machine and message schema
  Budgets/                 the manifesto's budgets as data, read by tests
Tests/SpeakboardCoreTests/ tests for the core
Tests/AllocationCounter/   test support: counts heap allocations (C, Linux), for tests only
DesignTokens/              the pinned design token export the metrics tables come from
scripts/                   the scripts behind make check, and the metrics generator
Makefile                   make check
.github/workflows/         CI: linux.yml runs make check, macos.yml the Xcode build, tests and
                           screenshots, on every push
Apple/Keyboard/            the keyboard extension: UIKit and Core Animation only, no SwiftUI
Apple/KeyboardKit/         linked into the extension (and the app's harness): its views, and
                           the only app or extension code that imports the core
                           (KeyboardKitTests imports it too)
Apple/KeyboardKitTests/    unit tests for KeyboardKit, run in the simulator
Apple/App/                 the containing app: SwiftUI
project.yml                XcodeGen definition of the targets; the .xcodeproj is never committed
```

These come later, with their own tickets:

```
Apple/KeyboardKit/         also: key rendering, haptics, IPC client
Apple/AppServices/         linked into the app only: audio, speech engines, storage,
                           anything that may touch the network
Evals/                     typing and dictation evaluation sets
```

Put logic in the core whenever you can. It is the fastest place to build and test.

Each file name must be unique within the core, even across folders. Swift requires it.

## Design tokens

Key geometry comes from one source: the design system's token export in Claude Design. A copy is pinned in `DesignTokens/`, beside the schema, validator and format note published with it. `DesignTokens/tokens.pin` records the design system's URL, the publish label, the token set version and each file's SHA-256.

`scripts/generate-metrics.swift` makes the core's metrics tables, `Sources/SpeakboardCore/Layout/GeneratedMetrics.swift`, from the pinned export: one row per device class and orientation, one column per token that varies by both, each cell with its value, tolerance, kind and placeholder flag. It copies every value as the export gives it. Never edit the tables or the pinned export by hand: `make check` fails on both.

To move to a new export:

1. Fetch the new `speakboard-tokens.json`, its schema, `validate-tokens.py` and `export-format.md` from the design system, at a named publish label.
2. Validate it with the schema published beside it: `python3 -I DesignTokens/validate-tokens.py DesignTokens/speakboard-tokens.json --schema DesignTokens/speakboard-tokens.schema.json --expect-sha256 <hash>` (add `--no-measured` while no value is measured). It needs Python 3, which the Swift image does not have, so run it on the host.
3. Update every line of `DesignTokens/tokens.pin`.
4. Run `make metrics`, then `make check`, and commit the export, the pin and the tables together.

## Formatting

The formatter is `swift-format`, which ships with Swift. Its settings are in `.swift-format`: 4-space indents, lines up to 120 characters, sorted imports, documentation on every public declaration, and no force unwraps or force `try` outside tests. swift-format does not apply those last two rules to test files.

Run `make format` to fix formatting. Then run `make check`.

## Testing report

Every builder returns a testing report in this form.

```
## Testing report: KEY-n

Commits: <first SHA>..<last SHA>
Rung: <1, 2, 3 or 4>, and what ran there

### Evidence
- `make check` on <commit>, from a clean state (no .build):
  <the tail of the output, ending with "make check: OK">
- <any other evidence: test output, screenshots>

### How each acceptance item was checked
- <item>: <how, and where the evidence is>

### Not checked
- <what was not checked, and why>

### Decisions not in the ticket
- <one line each>
```

## Definition of done

A ticket is done when all of these hold:

* Every acceptance item on the ticket is met, with evidence in the testing report.
* `make check` passes on the pushed head, from a clean state.
* The testing report names the rung, and says plainly what was not checked.
* A fresh reviewer approved the pushed commits, with no blocker or should-fix open.
* Every decision the ticket did not dictate is listed in the testing report.
* The orchestrator has recorded the review rounds and moved the ticket to Done.

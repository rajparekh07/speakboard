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
5. **Design tokens.** It checks that the pinned token export in `DesignTokens/` has the SHA-256 that `DesignTokens/tokens.pin` records, then runs the generator and fails if `Sources/SpeakboardCore/Layout/GeneratedMetrics.swift` differs from what it makes. See "Design tokens" below.
6. **Build.** `swift build`
7. **Tests.** `swift test`
8. **Format check.** `swift format lint --strict` on `Package.swift`, `Sources`, `Tests` and `scripts`.

It ends with `make check: OK`.

The Swift image is pinned to `swift:6.4.2-resolute` (Swift 6.4.2 on Ubuntu 26.04) in the `Makefile`. To change the Swift version, change `SWIFT_TAG` there, in its own commit.

The image is pinned by tag, not by digest. A tag can be re-pushed to point at a different image, and official images are rebuilt from time to time. On 15 Nov 2026, `swift:6.4.2-resolute` was the image with ID and digest `sha256:0384f00cf80f81064a907c249a0ad56a1648906f65075a95b1827e88de666e21`. Whether to pin by digest is the owner's call.

### In a fresh agent container

`make check` works in a fresh agent container with nothing set up. Expect two things on the first run:

* Nothing starts `dockerd`, so `make check` starts it in the background, as root. Its log is `/tmp/dockerd.log`.
* If `docker info` fails after the container's worker restarted, and `/tmp/dockerd.log` says "containerd is still running" for a process that no longer exists before `dockerd` exits, a stale `/var/run/docker/containerd/containerd.pid` is the cause. `make check` removes it, and the sockets beside it, before it starts `dockerd`, but only when no `dockerd` is running and the pid's process does not exist.
* The image is about 1.3 GB to download. Docker Hub rate-limits anonymous pulls, so `make check` pulls from `mirror.gcr.io/library/swift` first and from Docker Hub only if the mirror fails.

### Other targets

| Target | What it does |
| -- | -- |
| `make guard` | The core guard and its self-test only. Needs no Docker |
| `make guard-deps` | The core dependency guard and its self-test only |
| `make guard-imports` | The core imports guard and its self-test only |
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
7. The orchestrator records each round on the Linear ticket. It moves the ticket to Done once the approved commits are on the working branch and their checks pass. Approved work reaches `main` through the ticket's pull request, which the orchestrator merges once the ticket is approved (the owner's standing rule of 16 Nov 2026).

A fresh fixer replaces the builder when the same finding survives two rounds, when the findings say the approach is wrong, or when the builder's context has degraded. The orchestrator asks the owner before round 5 if a dispute survives a second reviewer, or if round 3 repeats round 2's findings.

## Where work lands

There are two branches (ADR-0021, which replaced the one-branch rule of ADR-0013 on 16 Nov 2026):

* `feature/sharp-einstein-aydugs` is the working branch. Every ticket is built on it and pushed to it, one repo-changing ticket at a time, and reviewed there. Reviews are recorded on the Linear ticket.
* `main` holds work a fresh reviewer has approved. It reaches `main` through a pull request from the working branch: one pull request per ticket, with any small follow-up ticket reviewed with it. The orchestrator opens it, and merges it once a fresh reviewer has approved the ticket (the owner's standing rule of 16 Nov 2026, recorded on ADR-0021). After a merge, the working branch continues from `main`. `main` is never red: nothing is merged unless the checks passed on the commit being merged.

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
| 2. macOS CI | GitHub Actions macOS runners | The Xcode project builds, simulator tests, screenshots | Not set up. It needs the Xcode project |
| 3. The owner's Mac | Remote Control from the Claude desktop app | Interactive Xcode, the simulator, Instruments | No Mac yet. Nothing depends on it |
| 4. A real iPhone | TestFlight | Latency, memory, battery, haptics, the app hop, the microphone. The only rung that proves a budget | No developer account or test iPhone yet |

Rung 1 also runs on GitHub. Every push to the working branch or to `main` runs `make check` on a GitHub-hosted Linux runner (`.github/workflows/linux.yml`), and each run uploads its log as the artifact `make-check-log`. Still run `make check` yourself before you push.

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
.github/workflows/         CI: linux.yml runs make check on every push
```

These come later, with their own tickets:

```
Apple/Keyboard/            the keyboard extension
Apple/KeyboardKit/         linked into the extension: key rendering, haptics, IPC client
Apple/App/                 the containing app
Apple/AppServices/         linked into the app only: audio, speech engines, storage,
                           anything that may touch the network
project.yml                XcodeGen definition of the targets
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

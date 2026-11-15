# Rules for agents

These are the binding rules for every agent that works in this repo. Read them before you change anything. How to do the work is in [CONTRIBUTING.md](CONTRIBUTING.md).

Speakboard is an iOS keyboard with dictation. The product position is [MANIFESTO.md](MANIFESTO.md).

## Order of authority

1. [MANIFESTO.md](MANIFESTO.md)
2. Accepted ADRs
3. This file, `AGENTS.md`
4. Tickets

If two of them disagree, the higher one wins. Do not resolve the conflict yourself: stop and tell the orchestrator. (ADR-0001)

ADRs are Linear documents. The [ADR index](https://linear.app/rajparekhinc-shared/document/architecture-decision-records-index-c7e653129398) lists each one and its status. Only the owner accepts an ADR. Silence is never acceptance. (ADR-0001)

Some rules below come from ADRs the owner has not accepted yet. Their status says "default in effect". Follow them as rules until the owner accepts or changes them.

## Where work lands

| Rule | Source | Status |
| -- | -- | -- |
| Everything lands on one branch, `feature/sharp-einstein-aydugs`. There is no `main`. Do not create a branch or a pull request. | [ADR-0013](https://linear.app/rajparekhinc-shared/document/adr-0013-branching-and-pull-requests-a352a7aec39f) | Accepted |
| Only one ticket that changes the repo is in flight at a time. Agents on other tickets write nothing into the checkout. | [ADR-0013](https://linear.app/rajparekhinc-shared/document/adr-0013-branching-and-pull-requests-a352a7aec39f) | Accepted |
| Every commit message starts with the ticket ID: `[KEY-n] subject`. A ticket is then one commit range. | [ADR-0013](https://linear.app/rajparekhinc-shared/document/adr-0013-branching-and-pull-requests-a352a7aec39f) | Accepted |
| Run `make check` and see it pass before you push. If the branch is red, nothing else lands until it is green. | [ADR-0013](https://linear.app/rajparekhinc-shared/document/adr-0013-branching-and-pull-requests-a352a7aec39f) | Accepted |

## Who does what

| Rule | Source | Status |
| -- | -- | -- |
| A builder builds one ticket and never reviews. A fresh reviewer reviews the pushed commits. A ticket gets at most 5 review rounds. | [ADR-0002](https://linear.app/rajparekhinc-shared/document/adr-0002-agents-build-fresh-reviewers-approve-five-rounds-at-most-f82a97fd491f) | Default in effect |
| The orchestrator moves tickets, comments on them and records review rounds. A builder does not. | [ADR-0002](https://linear.app/rajparekhinc-shared/document/adr-0002-agents-build-fresh-reviewers-approve-five-rounds-at-most-f82a97fd491f) | Default in effect |
| Every testing report names the rung that verified the work. A manifesto budget counts as met only on rung 4, a real iPhone. | [ADR-0004](https://linear.app/rajparekhinc-shared/document/adr-0004-four-rungs-of-build-and-test-access-d865ea998805) | Default in effect |

## Decisions

| Rule | Source | Status |
| -- | -- | -- |
| A choice that constrains more than one ticket, is costly to reverse, or extends or contradicts the manifesto needs an ADR. Do not make it in code. Tell the orchestrator. | [ADR-0001](https://linear.app/rajparekhinc-shared/document/adr-0001-decision-records-and-independent-opinions-020f0f8b23a9) | Default in effect |
| A smaller choice is the builder's. Note it in the testing report, so the orchestrator can record it on the ticket. | [ADR-0001](https://linear.app/rajparekhinc-shared/document/adr-0001-decision-records-and-independent-opinions-020f0f8b23a9) | Default in effect |
| Do not edit `MANIFESTO.md`. The orchestrator edits it, in its own commit, when an accepted ADR changes it. | [ADR-0001](https://linear.app/rajparekhinc-shared/document/adr-0001-decision-records-and-independent-opinions-020f0f8b23a9) | Default in effect |
| Work that rests on an ADR that is neither accepted nor a default in effect waits. Today that is ADR-0007, 0008, 0009, 0011 and 0012, and ADR-0014 to 0020, which are not drafted yet. | [ADR index](https://linear.app/rajparekhinc-shared/document/architecture-decision-records-index-c7e653129398) | |

## Code

| Rule | Source | Status |
| -- | -- | -- |
| Logic lives in the core, `Sources/SpeakboardCore`. The core is pure Swift with Foundation only, and builds and tests on Linux. | [ADR-0005](https://linear.app/rajparekhinc-shared/document/adr-0005-pure-swift-core-with-thin-apple-adapters-9e1a3f8a6951) | Default in effect |
| The core never imports `FoundationNetworking` and never uses `URLSession`. The core guard in `make check` fails if it does. | [ADR-0005](https://linear.app/rajparekhinc-shared/document/adr-0005-pure-swift-core-with-thin-apple-adapters-9e1a3f8a6951), manifesto principle 6 | Default in effect |
| Apple-only code lives under `Apple/` as thin adapters around the core. | [ADR-0005](https://linear.app/rajparekhinc-shared/document/adr-0005-pure-swift-core-with-thin-apple-adapters-9e1a3f8a6951) | Default in effect |
| The Xcode project is generated from `project.yml` with XcodeGen. Never commit an `.xcodeproj`. | [ADR-0006](https://linear.app/rajparekhinc-shared/document/adr-0006-xcode-project-generated-by-xcodegen-05b13e20a7b4) | Default in effect |
| English is the only launch language. Locale is still a parameter, and layouts, lexicons and rules are data per locale. | [ADR-0010](https://linear.app/rajparekhinc-shared/document/adr-0010-launch-languages-d5f0c6357a2f) | Accepted |
| What we invent is designed in Claude Design. What must match Apple comes from measurement, and every token says where it came from. Never draw Apple's keyboard from memory. | [ADR-0003](https://linear.app/rajparekhinc-shared/document/adr-0003-design-lives-in-claude-design-e6417a00634f) | Default in effect |

## From the manifesto

These rules have no ADR. They come straight from [MANIFESTO.md](MANIFESTO.md).

* The keyboard extension contains no networking code. (Principle 6, privacy contract 1)
* No private APIs, and no tricks that break on the next iOS release. (Principle 5)
* Budgets are law. A budget changes only through a measured argument in a reviewed change, recorded on its Linear ticket. (Budgets)
* The keystroke path allocates nothing. (Budgets)

## CI today

There is no CI yet. GitHub refused a workflow file, because the Claude GitHub App does not have the Workflows permission. That is an owner item, KEY-6. The Linux workflow arrives with KEY-7, once the owner grants the permission.

Until then, `make check` on rung 1 is the proof for core work. Do not add files under `.github/workflows/`, and do not try another way to get a workflow onto GitHub.

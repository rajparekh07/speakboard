# Rules for agents

These are the binding rules for every agent that works in this repo. Read them before you change anything. How to do the work is in [CONTRIBUTING.md](CONTRIBUTING.md).

Speakboard is an iOS keyboard with dictation. The product position is [MANIFESTO.md](MANIFESTO.md).

## Order of authority

1. [MANIFESTO.md](MANIFESTO.md)
2. Accepted ADRs
3. This file, `AGENTS.md`
4. Tickets

If two of them disagree, the higher one wins. Do not act on the lower one: stop and tell the orchestrator. (The order is ADR-0001 Part 2, default in effect. "Stop and tell the orchestrator" is a convention.)

ADRs are Linear documents. The [ADR index](https://linear.app/rajparekhinc-shared/document/architecture-decision-records-index-c7e653129398) lists each one and its status. Only the owner accepts an ADR. Silence is never acceptance. (ADR-0001 Part 2, default in effect)

## What the statuses mean

Each rule below names its source and its status.

* **Accepted:** the owner decided it. That is Part 1 of ADR-0001, 0002 and 0003, which is the owner's own instruction, and ADR-0010 and ADR-0013, which the owner answered.
* **Default in effect:** the ADR is proposed and not accepted. Follow it as a rule until the owner accepts or changes it.
* **Not an ADR:** the rule comes from the build plan (KEY-1), a ticket, or the orchestrator. It has the authority of this file, below every accepted ADR.

## Where work lands

| Rule | Source | Status |
| -- | -- | -- |
| Everything lands on one branch, `feature/sharp-einstein-aydugs`. There is no `main`. Do not create a branch or a pull request. | [ADR-0013](https://linear.app/rajparekhinc-shared/document/adr-0013-branching-and-pull-requests-a352a7aec39f) | Accepted |
| Only one ticket that changes the repo is in flight at a time. | [ADR-0013](https://linear.app/rajparekhinc-shared/document/adr-0013-branching-and-pull-requests-a352a7aec39f) | Accepted |
| If the branch is red, nothing else lands until it is green. | [ADR-0013](https://linear.app/rajparekhinc-shared/document/adr-0013-branching-and-pull-requests-a352a7aec39f) | Accepted |
| Agents on a ticket that does not change the repo write nothing into the checkout. Their working files go in a scratch folder outside it. | Build plan, section 2.3 | Not an ADR |
| Every commit message starts with the ticket ID: `[KEY-n] subject`. A ticket is then one commit range. | Build plan, section 2.3, and KEY-2 | Not an ADR |

## Who does what

| Rule | Source | Status |
| -- | -- | -- |
| Agents build. Fresh Opus 5.5 reviewers at high effort review. A ticket gets at most 5 review rounds. | [ADR-0002](https://linear.app/rajparekhinc-shared/document/adr-0002-agents-build-fresh-reviewers-approve-five-rounds-at-most-f82a97fd491f) Part 1 | Accepted |
| One new reviewer per round. Whether "a fresh set" means several per round is the owner's call. | [ADR-0002](https://linear.app/rajparekhinc-shared/document/adr-0002-agents-build-fresh-reviewers-approve-five-rounds-at-most-f82a97fd491f) Part 2 | Default in effect |
| A builder builds one ticket and never reviews. It runs `make check`, commits, and returns a testing report with evidence. It fixes the review findings on its own ticket. | [ADR-0002](https://linear.app/rajparekhinc-shared/document/adr-0002-agents-build-fresh-reviewers-approve-five-rounds-at-most-f82a97fd491f) Part 2 | Default in effect |
| The orchestrator records every review round on the Linear ticket and moves the ticket to Done. | [ADR-0002](https://linear.app/rajparekhinc-shared/document/adr-0002-agents-build-fresh-reviewers-approve-five-rounds-at-most-f82a97fd491f) Part 2 | Default in effect |
| A builder does not move tickets or comment on them. | The orchestrator | Not an ADR |
| Every testing report names the rung that verified the work. A manifesto budget counts as met only on rung 4, a real iPhone. | [ADR-0004](https://linear.app/rajparekhinc-shared/document/adr-0004-four-rungs-of-build-and-test-access-d865ea998805) | Default in effect |

## Decisions

| Rule | Source | Status |
| -- | -- | -- |
| A choice that constrains more than one ticket, is costly to reverse, or extends or contradicts the manifesto gets an ADR. Do not make it in code. Tell the orchestrator. | [ADR-0001](https://linear.app/rajparekhinc-shared/document/adr-0001-decision-records-and-independent-opinions-020f0f8b23a9) Part 2 | Default in effect |
| A builder decides anything smaller and notes it on the ticket. | [ADR-0001](https://linear.app/rajparekhinc-shared/document/adr-0001-decision-records-and-independent-opinions-020f0f8b23a9) Part 2 | Default in effect |
| Because a builder does not write to Linear, it lists those decisions in its testing report, and the orchestrator puts them on the ticket. | The orchestrator | Not an ADR |
| No work that depends on a blocking ADR starts before the owner accepts it. Today that is ADR-0007, 0008, 0009, 0011 and 0012, and ADR-0014 to 0020, which are not drafted yet. | [ADR-0001](https://linear.app/rajparekhinc-shared/document/adr-0001-decision-records-and-independent-opinions-020f0f8b23a9) Part 2, and the [ADR index](https://linear.app/rajparekhinc-shared/document/architecture-decision-records-index-c7e653129398) | Default in effect |
| An accepted ADR that changes the manifesto edits `MANIFESTO.md` in the same change, so the two never disagree. | [ADR-0001](https://linear.app/rajparekhinc-shared/document/adr-0001-decision-records-and-independent-opinions-020f0f8b23a9) Part 2 | Default in effect |
| Only the orchestrator edits `MANIFESTO.md`, in its own commit between tickets. A builder never edits it. | Build plan, section 2.4 | Not an ADR |

## Code

| Rule | Source | Status |
| -- | -- | -- |
| Logic lives in the core, `Sources/SpeakboardCore`. The core is pure Swift with Foundation only, and builds and tests on Linux. | [ADR-0005](https://linear.app/rajparekhinc-shared/document/adr-0005-pure-swift-core-with-thin-apple-adapters-9e1a3f8a6951) | Default in effect |
| The core never imports `FoundationNetworking` and never uses `URLSession`. The core guard in `make check` fails if it does. | [ADR-0005](https://linear.app/rajparekhinc-shared/document/adr-0005-pure-swift-core-with-thin-apple-adapters-9e1a3f8a6951) | Default in effect |
| The `SpeakboardCore` target in `Package.swift` declares no dependencies. The core dependency guard in `make check` fails if it does. | KEY-2, to enforce the rule above | Not an ADR |
| Apple-only code lives under `Apple/` as thin adapters around the core. | [ADR-0005](https://linear.app/rajparekhinc-shared/document/adr-0005-pure-swift-core-with-thin-apple-adapters-9e1a3f8a6951) | Default in effect |
| The Xcode project is generated from `project.yml` with XcodeGen. Never commit an `.xcodeproj`. | [ADR-0006](https://linear.app/rajparekhinc-shared/document/adr-0006-xcode-project-generated-by-xcodegen-05b13e20a7b4) | Default in effect |
| English is the only launch language. Locale is still a parameter, and layouts, lexicons and rules are data per locale. | [ADR-0010](https://linear.app/rajparekhinc-shared/document/adr-0010-launch-languages-d5f0c6357a2f) | Accepted |
| Design lives in Claude Design, made by a design agent. | [ADR-0003](https://linear.app/rajparekhinc-shared/document/adr-0003-design-lives-in-claude-design-e6417a00634f) Part 1 | Accepted |
| Claude Design is the source for what we invent. What must match Apple comes from measurement, and every token says where it came from. Never draw Apple's keyboard from memory. | [ADR-0003](https://linear.app/rajparekhinc-shared/document/adr-0003-design-lives-in-claude-design-e6417a00634f) Part 2 | Default in effect |

## From the manifesto

These rules have no ADR. They come straight from [MANIFESTO.md](MANIFESTO.md), which is above every ADR.

* The keyboard extension contains no networking code. (Principle 6, privacy contract 1)
* No private APIs, and no tricks that break on the next iOS release. (Principle 5)
* Budgets are law. A budget changes only through a measured argument in a reviewed change, recorded on its Linear ticket. (Budgets)
* The keystroke path allocates nothing. (Budgets)

## CI today

There is no CI yet. GitHub refused a workflow file, because the Claude GitHub App does not have the Workflows permission. That is an owner item, KEY-6. The Linux workflow arrives with KEY-7, once the owner grants the permission.

Until then, `make check` on rung 1 is the proof for core work. Do not add files under `.github/workflows/`, and do not try another way to get a workflow onto GitHub. (KEY-2, KEY-6 and KEY-7. Not an ADR.)

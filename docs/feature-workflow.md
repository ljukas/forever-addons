# How we build a new feature

The durable arc for taking a new addon, or a new capability in one, from idea to merge. This is the *meta-process* that produces the other artifacts. It is **not** an ADR (one decision), **not** a plan (one feature's build steps), and **not** a spec (one design).

Companions — one hat per commit, pick the doc by the hat:
- **[refactor-workflow.md](./refactor-workflow.md)** — behavior-preserving structural change.
- **[bugfix-workflow.md](./bugfix-workflow.md)** — observed behavior differs from intended behavior.

> **Run it:** `/feature-workflow <idea>` (`.claude/skills/feature-workflow/`) loads this doc and starts at Phase 0. Edit the process here, not in the skill.

> **Where the tools are.** The phases say *what* and *why*. *Which* skill or agent to use lives in [Current toolchain mapping](#current-toolchain-mapping): look up each phase's row there, and update that table (not the prose) when tooling changes. Entries tagged *(agent)* go through the `Agent` tool with that exact type; everything else is a skill for the `Skill` tool. Two exceptions name tools in the prose on purpose: the mandatory review gates (they're rules, not suggestions) and the [step reviewers](#step-reviewers) table.

> **Roadmap → step → task.** A feature bigger than one PR gets a roadmap (`docs/superpowers/roadmaps/`) split into **steps**: one plan, one session, one PR each. A step's plan is split into **tasks**. A feature that fits in one PR is a single step. **Review happens per step, not per task** (Phase 5); the one exception is the SavedVariables gate (Phase 4).

> **Before launch.** WoW Forever launches 4 November 2026. Until then nothing here has run in the client, and Phase 6 records what is untested instead of testing it. Say so plainly; never write "works" about code the game hasn't run.

---

## The shape in one line

**Isolate → Shape → Understand the seams → Plan → Build (task by task) → Review the step → Verify → Ship.** A worktree first, a brainstorm at the start and verification at the end, *always*, however small the feature feels.

---

## The phases

### 0. Isolate — always, first
**What:** Every feature starts in its own git worktree branched from `origin/main`, before the first file is written (a spec counts). Several Claude sessions work in this repo at once, and in one shared checkout they switch branches under each other; commits have landed on the wrong branch that way. There's no "too small for a worktree".

1. Create it with `EnterWorktree` and a short name: `.claude/worktrees/<name>` on a branch from `origin/main`.
2. Rename the branch to its conventional form: `git branch -m <type>/<slug>` (e.g. `feat/forevermap-node-counts`).
3. Run `scripts/worktree.sh setup`. It links `.cache/` and `.env.local` from the main checkout, so lint doesn't fetch the API reference again.
4. The game keeps loading addons from the main checkout. To test in game, `scripts/worktree.sh game` points the AddOns links at this worktree. Only one checkout is live at a time; `scripts/worktree.sh status` shows which. `scripts/worktree.sh restore` hands the links back, and must run before the worktree is removed. `scripts/new-addon.sh` in a worktree links just that new addon into the game from the worktree, without `game`.

Parallel work gets parallel worktrees. Never run two implementers in one worktree.

### 1. Shape the idea
**What:** Clarify intent, scope, constraints and success criteria *before* any code. Decide the **first slice** (the smallest thing that delivers the core value) and what's explicitly deferred. Surface the open product decisions the idea glossed over. Brainstorming is mandatory, even for "obviously simple" features, because that's where unexamined assumptions surface.
**Output:** An agreed scope, and a written **design record**:
- A real *decision with alternatives* (a SavedVariables layout, how two addons share data, which Blizzard frame to hook and how) → an **ADR** in `docs/adr/`. The first one starts the numbering at `0001`.
- Design detail that isn't a decision → a **spec** in `docs/superpowers/specs/`.

**Big features → a scope map first.** When the idea spans several shippable phases, write a **scope map** (a feasibility verdict per capability, then the phases), then one **design spec per phase** as you reach it. Feasibility here mostly means "can an addon do this at all under Midnight's restrictions?": which values come back secret, which actions are protected, what is blocked in combat or in instances.

**Probe the client before designing on it.** Designs built on assumed API behavior get rebuilt.
- Look every API up in `.cache/wow-ui-source` first: the generated docs for signatures, event payloads and the `Secret*` flags (`SecretArguments`, `SecretReturns`, the `SecretWhen…Restricted` family), and Blizzard's own code for how it uses them. Ketho's annotations in `.cache/wow-api` are Retail-based: they're no proof that something exists in Forever.
- Once the game is live, when the design hinges on runtime behavior the source can't show (is this payload secret in combat? does this event fire on login?), ship a logged probe first (in `addons/<Name>/Dev/`, or `addons/ForeverDev/Probes.lua` when it holds for every addon; CLAUDE.md → "Logging, probing and evidence"): `ns.log` the facts, `/rl`, read them with `scripts/devlog.sh --tag <TAG>`.
- Decide what the feature does when a value it needs is secret. That is part of the design, not an edge case.

**Native, not standalone.** Our addons extend Blizzard's UI: they hook existing frames, menus, tooltips, map canvases and the Settings panel, using Blizzard's own atlases, color constants and GlobalStrings, rather than adding windows or custom art. Shape the feature around where it lives in the base UI.

**Judgment — does the codebase fight this feature?** If adding it cleanly means restructuring first, do a **preparatory refactor** ("make the change easy, then make the easy change") under [refactor-workflow.md](./refactor-workflow.md), in its own PR, then come back. Never tangle the restructure into the feature.

### 2. Understand the seams
**What:** Map what already exists that the feature will *consume or reuse*, at the line level, before replicating anything. There are two kinds of seam:
- **Blizzard's:** mixins and templates, map canvas data providers, `TooltipDataProcessor`, `Menu.ModifyMenu`, `Settings`, `EventUtil` and `EventRegistry`, color constants, atlases. Find how Blizzard's own code uses each one in `.cache/wow-ui-source`; that is the usage to copy.
- **Ours:** the addon's `ns` modules, its `Database.lua` layout and migrations, ForeverDev's API (`ns.log`, `ns.dev`, `Knowledge.lua` evidence, `Dev/` probes), `template/Addon`, and the annotations in `types/forever.lua`.

Dispatch several explorers in parallel when the feature touches independent seams.

**Reuse before you hand-roll** (CLAUDE.md → "Code conventions"). For every non-trivial piece the design needs (timers, menus, options, tooltips, map pins, serialization), check in order:
1. a client facility, or code already in this repo;
2. a well-maintained library, added per addon through `.pkgmeta` externals (the repo uses none by default, so say why);
3. hand-rolling, only if neither fits, with the reason written in the design and the PR.

**Output:** A short list of seams and files to reuse, and every API the feature calls, checked against the Forever source with its secret flags.
**Judgment:** *When the design is already done (a detailed ADR/spec), don't run an architect pass.* The design is the architecture; exploration + Phase 3 cover the rest. Use an architect only for blank-page design.

### 3. Plan
**What:** Turn the design + the exploration findings into a **checkpointed, layered** plan, ordered by the addon's dependency spine:
`TOC (files, SavedVariables, metadata) → SavedVariables layout, defaults and migration → static data → engine (events, pure logic) → UI hooks (mixins, XML, atlases) → options (Settings) → slash commands and bindings → CHANGELOG`.

**Slice into PRs, one concern each.** Each PR must be shippable on its own and reviewable in one sitting. A big feature becomes a stack, e.g. data layer → engine with `ns.log` instrumentation → UI → options. Put the slicing in the plan.

**Name the step's reviewers.** The plan lists the specialists Phase 5 will add to the core reviewers (see [step reviewers](#step-reviewers)), and a **Review Focus** section: the few places most likely to be wrong, which every reviewer gets. Tasks don't name reviewers.

**List the launch checks.** Every assumption only the running client can confirm (a payload isn't secret, an event fires in that order, the art lines up) goes in the plan with the `ns.log` tag, `Dev/` probe or `Knowledge.lua` evidence that will show it. They become instrumentation in the tasks and the checklist in Phase 6.
**Output:** A plan in `docs/superpowers/plans/`.

### 4. Build, task by task
**What:** Execute the plan **one task at a time**, each through the same loop:
1. **Implement** the task. Verify each API in the Forever source before its first use, and add Forever-only APIs to `types/forever.lua` once verified. Add the `ns.log` tags, probes and evidence the launch checks need, the way CLAUDE.md → "Logging, probing and evidence" says (dev-only code stays out of releases). There's no automated test suite for addon code, so keep pure logic (parsers, matchers, math, layouts) in functions apart from event and frame code, where a reviewer can check it by reading. Run `scripts/lint.sh` until it's clean.
2. **Commit** it: one hat, a conventional message, `git add <paths>` (never `-A`), with `git branch --show-current` in the same command.
3. **Check the evidence:** a subagent implementer pastes `git log --oneline -N` and `git show --stat HEAD` into its report, and you check `HEAD` yourself before the next task. Reports of commits that don't exist happen.

There's no reviewer between tasks: review is per step (Phase 5). The loop still stays a per-task checkpoint in the conversation. Don't collapse it into one autonomous run.

**The SavedVariables gate is the one mid-step review.** When a task adds or changes what an addon stores (the TOC's `## SavedVariables*` lines, the DB layout, defaults, key formats, migrations), dispatch `savedvariables-guard` right after that task, and fix or rule on every finding **before any later task builds on the layout**. Players' saved data is the one thing a bad release can destroy for good. Phase 5 reviews it again in its final state.

**Honor the conventions** (CLAUDE.md → "Code conventions"): Lua 5.1; `local ADDON_NAME, ns = ...` and no globals beyond SavedVariables and client-required names, all prefixed with the addon name; `InCombatLockdown()` before protected actions and no touching secure frames in combat; never overwrite Blizzard functions or frame fields (`hooksecurefunc`, `EventRegistry` and mixins instead), because taint spreads; never compare, do arithmetic on or branch on a secret value (`issecretvalue`); every Lua/XML file loaded by the TOC; `ns.log`, never `print`.
**Parallelize the leaves, respect the spine.** TOC and SavedVariables → engine → UI is sequential; static data tables (spell lists, node tables), `types/` annotations and CHANGELOG lines can be farmed out.
**When something breaks:** debug systematically, never guess-patch.

### 5. Review the step
**What:** Once every task is built and committed, one adversarial review of the step's whole diff (`git fetch origin`, then `git diff origin/main...HEAD`); there's no separate branch review. **It must finish before merge**, and its findings are fixed *in this PR*.

1. **Dispatch every reviewer in parallel** (`Agent` tool, one message): the core reviewers plus every specialist the diff triggers ([step reviewers](#step-reviewers)), no cap. Each gets the diff range, the plan, the spec/ADR and the plan's Review Focus, and is told to *start from the assumption that the step is incorrect and not up to spec*. Reviewers make no edits.
2. **Verify each finding** against the code (and the Forever source) before fixing it: confirm it, or rule it out with a reason. More skeptical reviewers means more false positives; don't perform agreement.
3. **Fix** every confirmed finding in this PR, one commit per concern, then re-run the pre-PR gate (Phase 6).

#### Step reviewers
**Core, always:**
- `addon-reviewer` *(agent)*: the CLAUDE.md conventions, taint, combat lockdown, secret-value usage, native-UI extension, TOC metadata and CHANGELOG.
- `api-verifier` *(agent)*: every API, event, widget method, template and atlas the diff uses exists in the Forever source with that signature and allows the arguments passed; it lists which values read can be secret, for `addon-reviewer`. Mandatory whenever Lua or XML under `addons/` or `template/` changed: until launch it is the only check that the code calls things that exist.
- **Correctness reviewer** (`general-purpose`): bugs, nil paths, failure paths, event ordering on login and `/reload`, combat and instance behavior, across the whole diff.
- **Spec reviewer** (`general-purpose`): does the step do what the plan and spec say, all of it and nothing more? Missing tasks, silent design changes, scope creep, launch checks without the `ns.log` lines that would answer them.

**Specialists, one per layer the diff touches:**

| Diff touches | Add |
|---|---|
| SavedVariables, TOC `## SavedVariables*`, slash commands, bindings or settings keys | `savedvariables-guard` *(agent)*. Mandatory, on top of the [Phase 4 gate](#4-build-task-by-task) |
| UI: frames, XML, hooks into Blizzard UI, textures and atlases | **UI reviewer** (`general-purpose`): native look (Blizzard atlases, colors and GlobalStrings from `.cache/wow-ui-source`, no custom art), hooks into existing UI rather than new windows, anchoring and layering, secure frames left alone in combat |
| `scripts/` or `.github/` | **Shell reviewer** (`general-purpose`): correctness under `set -euo pipefail`, portability between macOS (BSD tools) and the Ubuntu CI runner, quoting of paths with spaces (`WOW_DIR` has them) |
| Packaging: `.pkgmeta`, TOC metadata, `scripts/package.sh`, `release.yml` | **Release reviewer** (`general-purpose`): packager directives (`@project-version@`, `#@do-not-package@` blocks), `LICENSE` in the zip, nothing dev-only shipped (ForeverDev, `Dev/` probes: do-not-package in the TOC and ignored in `.pkgmeta`) |

### 6. Verify end-to-end
**What:** Evidence before any "done" claim. Run the [pre-PR gate](#pre-pr-gate), then the in-game check that fits the date:
- **After launch:** `scripts/worktree.sh game`, then ask the user to `/rl` (a brand-new addon folder may need a client restart), to exercise the feature with the exact steps you give them, and to `/rl` again, because SavedVariables (and so the devlog) are only written on reload, logout or exit. Then `scripts/devlog.sh --errors` must show no Lua errors or blocked actions, and `scripts/devlog.sh --addon <Name>` (plus `scripts/observed.sh <Name>` for evidence) must show the launch-check tags with the values the plan expects. Anything else is a bug: [bugfix-workflow.md](./bugfix-workflow.md).
- **Before launch:** the game can't run it. Record the plan's launch checks as a project memory (`<addon>-launch-checks`, like the existing ForeverMap and ForeverCombat ones): what to do in game, which devlog tag and value confirms each assumption, and which file to change if it's wrong. The PR's *Testing* section says "untested in game".

### 7. Ship
**What:** Integrate the finished, green work: open the PR with `.github/pull_request_template.md` (*Summary*, and *Testing* with real evidence) and squash-merge. The PR title is the conventional-commit subject, and a `feat` or `fix` to an addon adds a players' line under `## Unreleased` in its `CHANGELOG.md`. CodeRabbit reviews every PR to `main` (`.coderabbit.yaml`, luacheck via `.luacheckrc`), and its pre-merge checks (player changelog, testing evidence, breaking-change marker) must pass before merge. Treat its comments like review findings: verify each, fix the real ones, reply to the rest. Before the worktree is removed, `scripts/worktree.sh restore`. Releasing is separate (CLAUDE.md → "Releasing an addon").
**Loop-back:** if the work changed a decision, amend the ADR (or add one). A gotcha that will recur in other addons belongs in CLAUDE.md or in a review agent's checklist.

---

## Pre-PR gate

Shared by all three workflows. It mirrors CI (the `CI` lint job and the PR-title check) and adds the checks CI can't do:

```sh
stylua addons template types                   # formats in place; commit anything it changed
scripts/lint.sh                                # = CI: StyLua check, LuaLS against the Forever source, TOC checks
scripts/check-pr-title.sh "<title>"            # = pr-title.yml
git fetch origin && git diff --stat origin/main...HEAD -- 'addons/*/CHANGELOG.md'   # a feat/fix added its players' line
```
- **APIs:** `api-verifier` found nothing missing from the Forever source (Phase 5).
- **In game:** after launch, `scripts/devlog.sh --errors` is clean for the session that exercised the change. Before launch, the launch checks are recorded and the PR says the change is untested in game.
- **PR title:** `<type>(<scope>): <subject>`, ≤72 chars, imperative, and one concern. CI checks only the format; the rest is on you.

Paste the output (or say what you checked) in the PR's *Testing* section. Unchecked claims are not evidence.

---

## Recurring judgment calls

- **A worktree, always.** Even for a one-line feature; the shared checkout belongs to whichever session switched it last.
- **Design done → skip the architect.** A detailed ADR/spec already *is* the architecture; spend the budget on real seams and a tight plan.
- **Look the API up; don't remember it.** Retail and Classic memories are wrong on Forever often enough. The generated docs for this build decide.
- **Secret values are a design input.** Decide in Phase 1 what the feature shows when a value is secret, rather than discovering it in combat.
- **Project agents beat a generic reviewer on project footguns** (API existence, SavedVariables, taint).
- **Skeptical reviewers, not confirming ones.** Tell reviewers to assume the work is wrong; an optimistic pass misses off-spec work.
- **The codebase fights you → switch hats first.** Preparatory refactor in its own PR, *then* the feature.
- **Blizzard first, then a library, then hand-roll.** A hand-rolled menu, timer or options panel is code we maintain and players notice isn't native.
- **Untested is a fact; state it.** Lint passing says nothing about runtime behavior.

---

## Which artifact am I producing?

| Artifact | Captures | Lives in |
|---|---|---|
| **ADR** | A decision *with alternatives* and why | `docs/adr/NNNN-*.md` |
| **Scope map** | Feasibility + phase breakdown for a multi-phase feature | `docs/superpowers/specs/*-scope-map.md` |
| **Spec** | Design detail for one phase that isn't a standalone decision | `docs/superpowers/specs/` |
| **Roadmap** | The steps of a feature bigger than one PR | `docs/superpowers/roadmaps/` |
| **Plan** | The checkpointed build sequence, PR slicing and launch checks for one step | `docs/superpowers/plans/` |
| **Launch checks** | What to verify in game, and how, once the client runs it | a project memory, `<addon>-launch-checks` |
| **Workflow** | The reusable process (this doc, refactor, bugfix) | `docs/*-workflow.md` (run via `.claude/skills/*-workflow/`) |

---

## Current toolchain mapping

*Where tools are listed (the prose names only mandatory gates). Entries tagged* (agent) *go through the `Agent` tool; the rest are skills. Update this section when tooling changes; the phases above stay durable.*

| Phase | Primary | Also useful |
|---|---|---|
| 0. Isolate | `EnterWorktree` *(tool)*, then `scripts/worktree.sh setup` | `superpowers:using-git-worktrees` *(only where no native worktree tool exists)* |
| 1. Shape | `superpowers:brainstorming` | `AskUserQuestion` for genuine forks; the `.cache/wow-ui-source` searches in CLAUDE.md → "Looking up the API"; Context7 *(tooling docs: StyLua, LuaLS, the BigWigs packager)* |
| 2. Understand seams | `feature-dev:code-explorer` *(agent)* | `Explore` *(agent)*; `superpowers:dispatching-parallel-agents`; `feature-dev:code-architect` *(agent; blank-page design only)* |
| 3. Plan | `superpowers:writing-plans` | `Plan` *(agent; smaller features)* |
| 4. Build | `superpowers:subagent-driven-development` (this session) / `superpowers:executing-plans` (inline, no subagents) | `superpowers:systematic-debugging`; `superpowers:dispatching-parallel-agents` *(leaves)*; the SavedVariables gate (`savedvariables-guard`, layout tasks only); `scripts/lint.sh` after every task |
| 5. Review step | Core: `addon-reviewer`, `api-verifier` *(agents)*, correctness + spec reviewers *(`general-purpose` agents)*; specialists per [step reviewers](#step-reviewers): `savedvariables-guard` *(agent)*, UI / shell / release reviewers *(`general-purpose` agents)* | `/code-review` (`high`+ for large diffs; `--fix` to apply); `/simplify`; `superpowers:requesting-code-review` / `superpowers:receiving-code-review`; the `Workflow` tool for a multi-agent review *(only when the user opts in)* |
| 6. Verify | `superpowers:verification-before-completion` | `scripts/worktree.sh game`; `scripts/devlog.sh` (`--addon`, `--tag`); `scripts/observed.sh`; `scripts/combat-knowledge.sh` *(ForeverCombat)* |
| 7. Ship | `superpowers:finishing-a-development-branch` | CodeRabbit *(automatic on the PR)*; `superpowers:receiving-code-review` *(its findings)*; `claude-md-management:revise-claude-md` *(capture session learnings)* |

# How we refactor

The durable arc for **behavior-preserving structural change**: making code easier to understand and cheaper to change *without changing what it observably does*.

Companions: **[feature-workflow.md](./feature-workflow.md)** for adding capability, **[bugfix-workflow.md](./bugfix-workflow.md)** for fixing wrong behavior. All three are governed by one rule:

> **The prime directive — one hat at a time (Kent Beck's "Two Hats").**
> A refactor changes *internal structure only*; observable behavior stays identical and checks stay green throughout (Fowler). Adding a feature or fixing a bug is the *other* hat. **Never wear both in the same commit.** If your change alters behavior, it isn't a refactor: it belongs in the feature or bugfix workflow. Keep refactor commits pure so any diff is *all-structure* or *all-behavior*; that's what makes review and rollback tractable.

> **Run it:** `/refactor-workflow <target>` (`.claude/skills/refactor-workflow/`) loads this doc and starts at Phase 0. Edit the process here, not in the skill.

> **Where the tools are.** The phases say *what* and *why*. *Which* skill or agent to use lives in [Current toolchain mapping](#current-toolchain-mapping); update that table, not the prose, when tooling changes. The prose names only mandatory review gates.

---

## The shape in one line

**Isolate → Confirm & size → Safety net → Decide the target → Pick a strategy → Small steps → Verify preservation → Review & ship.** Safety net first, evidence at the end.

---

## The phases

### 0. Isolate — always, first
**What:** A fresh worktree from `origin/main` before the first edit, with a `refactor/<slug>` branch. Same steps as [feature-workflow.md → Phase 0](./feature-workflow.md#0-isolate--always-first).

### 1. Confirm it's a refactor, and size it
**What:** Two checks. (1) *Behavior-preserving?* If you're adding capability or fixing a bug, stop: wrong doc. (2) *How big?*
- **Opportunistic** (the campsite rule, "leave it better than you found it"): a bounded cleanup in code you're already touching. This is the **default**; it needs no ceremony beyond the safety net and one-hat discipline.
- **Planned / large**: a structural change big or risky enough to need a named strategy (Phase 4) and usually a plan. The exception, not the rule. (Fowler: a team refactoring well "should hardly ever need to plan refactoring.")
- **Preparatory** (for an upcoming feature): its own PR, landed before the feature, so the feature reuses a seam instead of copying code.

### 2. Establish the safety net — *first*
**What:** You can only *assert* behavior was preserved if something checks it. There's no automated test suite for addon code, so the net is built from what the repo has, and you need it in place before touching structure:
- **`scripts/lint.sh` clean before you start.** LuaLS catches undefined globals and wrong API calls against the Forever source. It does **not** catch a misspelled or moved `ns.` field: `ns` is an untyped table. After every move or rename, grep for the old name across `addons/`.
- **Characterization in game (after launch):** before restructuring, have the user run a fixed set of in-game steps and `/rl`, and keep that `scripts/devlog.sh` output. The same steps after the refactor must produce the same log lines and no new errors. Add `ns.log` lines first where the code you're moving logs nothing.
- **Pure logic** (parsers, matchers, math): write down a few input → output examples from the current code (bugs included: you're pinning *what is*, not *what should be*) and check them by trace after the change.

**Rule:** **no safety net → no refactor.** Before launch the in-game net doesn't exist, so limit pre-launch refactors to mechanical ones that lint and grep can verify (moves, renames, extractions), or write the characterization steps as a launch check and refactor once it has run.

### 3. Decide what to refactor *toward*
**What:** A refactor needs a destination. We use the vocabulary of **John Ousterhout's *A Philosophy of Software Design***:
- **Deepen modules**: powerful functionality behind a *simple* interface; push complexity *down*, not sideways into more small files.
- **Hide information**: each module hides a decision (a format, an algorithm, a Blizzard quirk). ForeverProfessions' `Database.lua` is the model: it is the only file that knows the flat node layout. Target *information leakage*, where one decision is smeared across modules.
- **Reduce complexity** = reduce **dependencies** and **obscurity**, the two things that make change hard. "Does this lower net complexity?" is the acceptance test.
- **Define errors out of existence**: redesign an API so an edge case *can't arise* instead of making every caller handle it, e.g. one module that resolves a possibly-secret value once instead of `issecretvalue` checks at every call site.
- **The deletion test**: if you deleted this module, would complexity reconcentrate elsewhere? If not, it's *shallow* and shouldn't exist.

**Judgment — design is a human call.** This is the one phase AI agents are *weak* at (they rearrange more than they deepen). Decide the target with judgment; use agents for the mechanics (Phase 5).

### 4. Pick a strategy sized to the risk
**Small / local** → just take small steps (Phase 5). Catalog moves: Extract/Inline Function, Move, Rename, Replace Conditional with Polymorphism.

**Large / risky** → pick a named strategy so the code stays shippable throughout:

| Strategy | What it is | Use when |
|---|---|---|
| **Mikado Method** | Attempt the change; when it breaks, note the prerequisite, **revert**, recurse into a dependency graph; then execute leaves-first, each landing on green `main`. | Many tangled, *unknown* prerequisites; you want to avoid a branch that's broken for weeks. |
| **Strangler Fig** | Route through a facade, build the replacement behind it piece by piece, redirect gradually, delete the old once nothing routes to it. | Replacing a hand-rolled subsystem (a custom frame, a hand-rolled menu) with the Blizzard facility behind one module. |
| **Branch by Abstraction** | Introduce an abstraction in front of the thing, migrate all callers to it, build the new impl behind it, flip the default, delete the old. | Replacing something **many call sites depend on** inside an addon: a shared helper, the `ns.DB` interface. |
| **Parallel Change** (expand → migrate → contract) | Add the new form alongside the old, move all callers/data over, then remove the old. | Changing a widely-used interface, or the **SavedVariables layout**: the migration on load is the "migrate" step, and the reader of the old shape goes only once the migration has shipped. |

**Code shared between addons.** Each addon ships as its own zip, so there is no shared runtime module. Code two addons need is either copied or packaged as a library through `.pkgmeta` externals. Decide that explicitly; don't let an addon reach into another's globals.

#### Replacing hand-rolled code with a Blizzard facility or a library
A swap is a refactor *only if behavior stays the same*, and Blizzard's facilities rarely match hand-rolled code exactly. Treat it as Branch by Abstraction around the old helper:
1. **Pin the current behavior** on the edge cases the hand-rolled code handles on purpose: ordering, cancellation, what happens on `/reload` and in combat, what happens with a secret value.
2. **List the semantic gaps** between the old code and the replacement by reading Blizzard's *current* source in `.cache/wow-ui-source` (or the library's current docs), not memory.
3. **Rule on each gap:** configure or wrap the replacement so behavior is identical (stays a refactor), or change behavior deliberately (that's the *other* hat: a separate `fix`/`feat` commit, stated in the PR).
4. **Delete the old code**, and any `.pkgmeta` external it leaves unused.
5. **One PR per swap**, so a regression bisects to one swap.

### 5. Execute in small behavior-preserving steps
**What:** Make the smallest structural change, **run `scripts/lint.sh`, grep for leftovers of the old names, commit**, then the next. Many tiny verified steps compose into the large transformation without ever leaving working code. **One hat per commit. Diffs small enough to actually review.**
- Fan out *independent mechanical* edits (renames, extractions across files); that's where agents are strong.
- New files go in the TOC in the right load order: a module that another file uses at load time must load first. Lint checks the file is listed, not the order.
- Planned/large refactors run the same **task loop** as features ([feature-workflow.md → Phase 4](./feature-workflow.md#4-build-task-by-task)): one step at a time, git evidence checked, no reviewer in between (except the SavedVariables gate). Review happens once, over the whole branch, in Phase 7.

### 6. Verify behavior preservation
**What:** The whole point: *prove* nothing observable changed, don't assert it. Run the [pre-PR gate](./feature-workflow.md#pre-pr-gate), grep for every old name once more, and after launch repeat the characterization steps from Phase 2 (`scripts/worktree.sh game`, the same steps, `/rl`) and compare the devlog output. For UI, check it looks and anchors the same in game. Before launch, say in the PR which checks ran and which wait for launch.

### 7. Review & ship
**What:** Review the whole branch, then integrate. Same shape as the feature workflow's [step review](./feature-workflow.md#5-review-the-step): every reviewer in parallel, each told to *assume the refactor changed behavior*; verify each finding before fixing it.
- Core, always → `addon-reviewer`, a correctness reviewer looking for behavior that moved (load order, event registration timing, a `ns.` field that no longer resolves), and a target reviewer: did the change reach the target decided in Phase 3, and nothing beyond it?
- Moved or changed calls into the client → `api-verifier`.
- Touched what an addon stores, its slash commands or settings keys → `savedvariables-guard` (mandatory).
- Moved UI → the UI reviewer from the [step reviewers](./feature-workflow.md#step-reviewers), told to look for rendering, anchoring or hooking that changed.
- Open the PR with the template; `refactor(<scope>): …` title; no CHANGELOG line (players see no change); squash-merge. `scripts/worktree.sh restore` before the worktree is removed.

**Loop-back:** *if the refactor changed an architectural decision*, record it: an ADR amendment or a new ADR, and update CLAUDE.md if a convention moved.

---

## Refactoring with AI agents — safely

This repo is largely built with AI agents, and the empirical record is specific: agents are **strong at mechanical, local edits** (rename, extract, signature changes) and **weak at design-level deepening** (they rearrange far more than they reduce real complexity). Hard rules:

1. **Lock behavior first.** Never let an agent refactor without the safety net from Phase 2, and **verify** preservation (lint, grep, devlog comparison) instead of trusting its claim of equivalence. LLMs produce *plausible*, not *provably equivalent*, code.
2. **One hat per commit.** Agents routinely produce **tangled commits** (structure + behavior mixed), the single biggest review hazard. Reject them.
3. **Keep diffs small and reviewable.** If you can't review it, you can't trust it. One transformation per agent task.
4. **Humans/judgment own the design target** (Phase 3). Agents execute the *what*; they don't decide it. No speculative "future-proofing" abstractions.

---

## Pitfalls

- **Big-bang rewrite**: long stretches with nothing shippable. Prefer the incremental strategies (Phase 4).
- **No safety net**: characterize first, or keep the refactor mechanical.
- **A moved `ns.` field nobody greps for**: lint stays green and the addon errors on load.
- **Mixing hats / scope creep**: a "small cleanup" balloons or smuggles in behavior change. Time-box opportunistic cleanups; defer the rest.
- **A swap that quietly changes semantics**: a Blizzard facility has its own opinions about ordering, combat and reload. List the gaps (Phase 4) before swapping.
- **Speculative generality (YAGNI)**: abstractions for futures that never arrive. Refactor *toward today's* needs.
- **Refactoring code you don't understand**: you'll "preserve" behavior you've actually broken. Characterize first; smaller steps.

---

## A noted tension (so we resolve it the same way each time)

Ousterhout is skeptical of strict TDD; Beck/Fowler treat tests as the indispensable safety net. We use **both, for different jobs**: **a safety net lets you refactor safely** (Phases 2, 5, 6), and here that net is lint, grep and devlog characterization rather than a test suite; **APOSD judgment decides what to refactor *toward*** (Phase 3). A thin net means smaller steps, never skipping the net.

---

## Current toolchain mapping

*Where tools are listed (the prose names only mandatory gates). Entries tagged* (agent) *go through the `Agent` tool; the rest are skills. Update this section when tooling changes; the phases above stay durable.*

| Phase | Primary | Also useful |
|---|---|---|
| 0. Isolate | `EnterWorktree` *(tool)*, then `scripts/worktree.sh setup` | — |
| 1. Confirm & size | — | `feature-dev:code-explorer` *(agent)*; `Explore` *(agent)* |
| 2. Safety net | `scripts/lint.sh`; `scripts/devlog.sh` *(characterization, after launch)* | `scripts/worktree.sh game` |
| 3. Decide target | *(human/judgment — APOSD)* | `feature-dev:code-architect` *(agent)* |
| 4. Pick strategy | `superpowers:writing-plans` *(planned/large)* | `Plan` *(agent)*; `.cache/wow-ui-source` *(a swap's gap list)* |
| 5. Small steps | `code-simplifier:code-simplifier` *(agent)* / `/simplify` *(mechanical cleanup; quality only, no bug hunting)* | `superpowers:subagent-driven-development`; `superpowers:dispatching-parallel-agents`; `superpowers:systematic-debugging` |
| 6. Verify preservation | `superpowers:verification-before-completion` | `scripts/devlog.sh` *(before/after comparison)* |
| 7. Review & ship | `addon-reviewer`, `api-verifier`, `savedvariables-guard` *(agents)*; correctness + target reviewers *(`general-purpose` agents)* | `/simplify`; `/code-review` (`--fix` to apply); `superpowers:requesting-code-review` / `superpowers:receiving-code-review`; `superpowers:finishing-a-development-branch` |

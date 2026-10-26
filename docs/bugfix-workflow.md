# How we fix a bug

The durable arc for making **observed behavior match intended behavior**: find the real cause, pin it with evidence, fix only that, and prove it's gone.

Companions — one hat per commit:
- **[feature-workflow.md](./feature-workflow.md)** — the "fix" actually needs new capability, or *intended* behavior was never decided.
- **[refactor-workflow.md](./refactor-workflow.md)** — the fix would be easy if the code were shaped differently. Refactor first, in its own commit or PR, then fix.

> **Run it:** `/bugfix-workflow <symptom>` (`.claude/skills/bugfix-workflow/`) loads this doc and starts at Phase 0. Edit the process here, not in the skill.

> **Where the tools are.** The phases say *what* and *why*. *Which* skill or agent to use lives in [Current toolchain mapping](#current-toolchain-mapping). The prose names only mandatory review gates.

> **Before launch** (4 November 2026) the client can't run anything, so a bug is something found by reading: a review finding, or code that contradicts the Forever source. Reproduce and verify by tracing through the code and the source, and record what only the game can confirm as a launch check.

---

## The shape in one line

**Isolate → Confirm it's a bug → Reproduce → Find the root cause → Pin it → Minimal fix → Verify → Review & ship.** No fix without a cause; no cause without a repro.

---

## The phases

### 0. Isolate — always, first
**What:** A fresh worktree from `origin/main` before the first edit; `ns.log` probes are edits too. Same steps as [feature-workflow.md → Phase 0](./feature-workflow.md#0-isolate--always-first), with a `fix/<slug>` branch. To reproduce in game, `scripts/worktree.sh game` points the game at the worktree; `scripts/worktree.sh restore` before it's removed.

### 1. Confirm it's a bug, and gather evidence
**What:** A bug is behavior that contradicts something already decided: a spec, an ADR, a CLAUDE.md convention, or plain correctness. If nobody decided what *should* happen, it's a product decision, so switch to the feature workflow.
**Evidence first, theories second.** Collect what actually happened before guessing why:
- **In game:** `scripts/devlog.sh` (Lua errors with stack traces, `ADDON_ACTION_BLOCKED`/`ADDON_ACTION_FORBIDDEN` taint events, `ns.log` lines; `--all` for earlier sessions, `--errors` for errors only, `--addon NAME` and `--tag TAG` to narrow it down) and `scripts/observed.sh` for the evidence addons keep across sessions. `/fdev errors` lists the session's errors in chat. Ask for `/rl` after the bug shows: nothing reaches disk before it.
- **The circumstances:** the user's exact steps, class and spec, zone and whether it was an instance, in combat or not, and which other addons were loaded. Taint is often another addon's fault, and secret values depend on all of these.
- **Review findings:** each finding is a bug report. Confirm it's real against the code and the Forever source before fixing it.

### 2. Reproduce
**What:** Get the smallest reliable reproduction. Claude can't play, so a repro is exact in-game steps for the user plus the devlog output that shows the bug. When the devlog doesn't say enough, add an `ns.log` line at the suspected point, have the user repeat the steps and `/rl`, and read it again.
Before launch, a repro is a written trace through the code and the Forever source that arrives at the wrong behavior, marked unconfirmed.
Can't reproduce? Keep gathering evidence (Phase 1) rather than fixing blind. A fix for an unreproduced bug is a guess, and you can't show it worked.

### 3. Find the root cause
**What:** Trace from the symptom to the *first* place behavior goes wrong, not the place it becomes visible. For a blocked action, that's the first tainted write (an overwritten Blizzard field, a global from addon code), not the protected call the devlog names. Then ask two questions:
- **Where else does this pattern appear?** The same mistake usually lives in sibling code: the same API misused in another module or another addon, the same secret value compared elsewhere. Fix the class of bug, not the one instance, but in scope: list the other sites and fix them in the same PR only if they share the cause.
- **Is this the second or third fix here?** Repeated fixes to one area mean the design is fighting you. Stop and question the approach (often: stop hand-rolling what a Blizzard facility does) before adding another patch.

### 4. Pin it
**What:** There's no automated test suite for addon code, so pin the bug with the strongest check available, and get it showing the wrong behavior *before* the fix:
- **An `ns.log` tag** at the root cause that logs the wrong value now and will log the right one after. Keep it when it's useful instrumentation; remove it when it's noise.
- **A LuaLS diagnostic**, when the bug was a wrong call: an annotation in `types/forever.lua` that makes the mistake a lint error, so it can't come back.
- **Pure logic** (parsers, matchers, math): a worked example in the PR (input, wrong output, right output) that a reviewer can check by reading.

Before launch, the tag's expected values become a launch check.

### 5. Make the minimal fix
**What:** Change only what the root cause requires. **One hat:** no drive-by refactors or cleanups in the fix commit. If the fix needs restructuring, land that as a separate `refactor` commit first, under the refactor workflow's safety-net rules.
The fix still honors the CLAUDE.md conventions. A change to what an addon stores still gets `savedvariables-guard`, even in a hurry, and if the bug wrote bad data into players' SavedVariables, the fix includes a migration that repairs it.

### 6. Verify
**What:** The check from Phase 4 now shows the right behavior, the original repro no longer reproduces (rerun it; don't only check the new tag), `scripts/devlog.sh --errors` is clean, and the [pre-PR gate](./feature-workflow.md#pre-pr-gate) is green. Before launch: the fix is checked by trace and the PR says it's untested in game.

### 7. Review & ship
**What:**
- `addon-reviewer` and `api-verifier`, plus a reviewer told to assume the fix is incomplete: does it cover the sibling sites from Phase 3, and does the Phase 4 check actually show the bug without the fix?
- The project gates as they apply: `savedvariables-guard` for stored data, slash commands or settings; the UI reviewer for frame and hook changes ([step reviewers](./feature-workflow.md#step-reviewers)).
- PR with the template: *Summary* names the symptom and the root cause; `fix(<addon>): …` title; a players' line under `## Unreleased` in the addon's `CHANGELOG.md`; squash-merge. A batch of review findings can ship as one PR for that review round, with the *Summary* listing each finding; don't open one PR per finding.
- `scripts/worktree.sh restore` before the worktree is removed.

**Loop-back:** if the bug showed a *decision* was wrong, amend the ADR. A mistake that could recur in other addons belongs in CLAUDE.md or a review agent's checklist (often `api-verifier`'s or `addon-reviewer`'s).

---

## Pitfalls

- **Fixing the symptom:** a `pcall` or an early `return` that hides the error instead of removing its cause. An `issecretvalue` guard that quietly turns the feature off in combat is a product decision; make it on purpose and say so.
- **No check that pins it:** the bug comes back in the next refactor.
- **Patch stacking:** the third fix in one area is a design problem, not a bug.
- **Scope creep:** "while I'm here" refactors in the fix commit make the fix unreviewable and unrevertable.
- **Trusting "fixed" without the repro:** rerun the original steps, not only the new log line.
- **Fixing from Retail memory:** check how the API behaves in the Forever source, not how it behaved elsewhere.

---

## Current toolchain mapping

*Where tools are listed (the prose names only mandatory gates). Entries tagged* (agent) *go through the `Agent` tool; the rest are skills. Update this section when tooling changes; the phases above stay durable.*

| Phase | Primary | Also useful |
|---|---|---|
| 0. Isolate | `EnterWorktree` *(tool)*, then `scripts/worktree.sh setup` | `scripts/worktree.sh game` *(to reproduce in game)* |
| 1. Evidence | `scripts/devlog.sh` | `scripts/observed.sh`; `/fdev errors` *(in game)*; `scripts/combat-knowledge.sh` *(ForeverCombat)* |
| 2. Reproduce | `superpowers:systematic-debugging` | `ns.log` probes + `scripts/devlog.sh` |
| 3. Root cause | `superpowers:systematic-debugging` | `feature-dev:code-explorer` *(agent)*; `Explore` *(agent)*; the `.cache/wow-ui-source` searches in CLAUDE.md |
| 4. Pin it | — | `types/forever.lua` *(annotations that make a wrong call a lint error)* |
| 5. Minimal fix | — | `refactor-workflow` *(if restructuring is needed first)*; `savedvariables-guard` *(agent; stored data)* |
| 6. Verify | `superpowers:verification-before-completion` | `scripts/devlog.sh --errors` |
| 7. Review & ship | `addon-reviewer`, `api-verifier` *(agents)*, plus `savedvariables-guard` *(agent)* and the UI reviewer as applicable | `/code-review`; `superpowers:receiving-code-review`; `superpowers:finishing-a-development-branch` |

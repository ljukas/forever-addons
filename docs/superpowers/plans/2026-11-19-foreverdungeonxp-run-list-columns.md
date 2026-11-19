# ForeverDungeonXP Run List Columns Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The journal's run list gets three headings that name their columns, `Dungeon | Level |
XP/h`, and a click on `XP/h` ranks every listed run by experience per hour in one flat list.

**Architecture:** The ordering stays in the pure `Logic/RunList.lua`, which takes a third sort key
(`"rate"`) and puts each run's rate on its row. `UI/Journal.lua` adds the heading and fills two
number columns in the run row (`UI/Templates.xml`). Nothing saved changes.

**Tech Stack:** Lua 5.1 on the Forever client (interface 16001), Blizzard's
`ColumnDisplayButtonNoScriptsTemplate` and ScrollBox, already used by the journal. No automated
tests exist for addon code; the pure logic is exercised with LuaJIT from a scratch script, the
rest with `scripts/lint.sh` and in game.

**Spec:** `docs/superpowers/specs/2026-11-19-foreverdungeonxp-run-list-columns-design.md`

One PR: `feat(foreverdungeonxp): rank the run list by experience per hour`.

## Global Constraints

- `ForeverDungeonXPDB` is only read: no new saved field, no `DB_VERSION` change.
- No new global, no new file (so no TOC change), no new client API: only what `UI/Journal.lua`
  already calls.
- Strings in `ns.L` (`Strings.lua`), plain ASCII.
- Logging through `ns.log` with the existing tag `UI`; work done only for a log line goes inside
  `if ns.dev.enabled then`.
- The rate is one number everywhere: `ns.Format.PerHour(run.xp, ns.Format.RunSeconds(run))`,
  rested bonus included, nil for a run shorter than a minute.
- After every task: `stylua addons template types` and `scripts/lint.sh` clean, then one commit
  with `git add <paths>` and `git branch --show-current` in the same command.

## Review Focus

1. **Runs without a rate** (shorter than a minute, or without `firstKill` / `lastKill`): they
   stand last in the flat list in both directions and show "-". The comparator must never compare
   nil with a number.
2. **The comparator is a strict order.** Equal rates, and two runs without a rate, fall back to
   newest first; an inconsistent comparator makes `table.sort` throw "invalid order function".
3. **A run without `level`** (damaged or hand-edited data): the row shows "-", the list doesn't
   throw.
4. **The run being recorded** in the flat list: its rate changes with every kill, so the list
   reorders while open. The selection must stay on the same run.
5. **Labels over columns:** each heading's label must stand over its column's numbers. The offsets
   in Task 2 are derived from the row template's anchors; a change to one needs the other.

---

### Task 1: The rate order in the pure logic

**Files:**
- Modify: `addons/ForeverDungeonXP/Logic/Format.lua`
- Modify: `addons/ForeverDungeonXP/Logic/RunList.lua`
- Check (not committed): a LuaJIT script in the session's scratchpad

**Interfaces:**
- Produces: `ns.Format.Rate(run) -> number|nil`, the run's experience per hour.
- Produces: `ns.RunList.Rows(entries, sortKey, ascending)` accepts `sortKey == "rate"`: no header
  rows, the entries ordered by rate (`ascending` lowest first, else highest first), entries
  without a rate last in both directions, ties newest first. In every mode each listed entry gets
  `entry.rate = ns.Format.Rate(entry.run)`.

- [ ] **Step 1: Write the check.** A script that builds a bare `ns`, loads `Strings.lua`,
  `Logic/Format.lua` and `Logic/RunList.lua` with `loadfile(path)("ForeverDungeonXP", ns)`, and
  asserts on these runs (xp, firstKill, lastKill, level, instanceID, name), all with `kills = 5`:

  | id | xp | first | last | rate |
  | --- | --- | --- | --- | --- |
  | 1 | 9418 | 1000 | 3640 | 12843 |
  | 2 | 13994 | 5000 | 6860 | 27085 |
  | 3 | 500 | 8000 | 8030 | nil |
  | 4 | 7528 | 9000 | 10500 | 18067 |
  | 5 | 400 | nil | nil | nil |
  | 6 | 9418 | 2000 | 4640 | 12843 |

  Assertions: `Rate` gives the table's values; `"rate"` descending gives ids `2, 4, 6, 1, 3, 5`
  with no row having `header`; ascending gives `6, 1, 4, 2, 3, 5`; a run with `kills = 0` is left
  out; `"dungeon"` and `"level"` give the same rows as before (headers, newest first inside a
  group) and every run row has `rate` set as in the table; sorting 200 runs of which half share a
  rate and a tenth have none does not throw.

- [ ] **Step 2: Run it and see it fail.** `luajit <script> <addon dir>`; expected: fails on
  `ns.Format.Rate` being nil.

- [ ] **Step 3: Add `ns.Format.Rate(run)`** to `Logic/Format.lua`, after `RunSeconds` (it needs
  it), with a comment giving one worked example.

- [ ] **Step 4: Add the `"rate"` order** to `ns.RunList.Rows`. Set `entry.rate` where the entries
  are filtered (once per entry, not in the comparator). For `"rate"` return the filtered entries
  sorted, with no grouping. Update the function's comment: the three sort keys, and that rows
  carry `rate`.

- [ ] **Step 5: Run the check again.** Expected: every assertion passes.

- [ ] **Step 6: Lint and commit.** `feat(foreverdungeonxp): order runs by experience per hour`

### Task 2: The columns, the heading and the width

**Files:**
- Modify: `addons/ForeverDungeonXP/Strings.lua`
- Modify: `addons/ForeverDungeonXP/UI/Templates.xml` (the run row)
- Modify: `addons/ForeverDungeonXP/UI/Journal.lua`
- Modify: `addons/ForeverDungeonXP/CHANGELOG.md`

**Interfaces:**
- Consumes: `ns.RunList.Rows(..., "rate", ascending)` and `data.rate` on run rows (Task 1).

- [ ] **Step 1: Strings.** `COLUMN_RATE = "XP/h"`; `RUN_SUMMARY = "%s XP (%s) - %s - %s"`
  (experience, share of a level, kills, time).

- [ ] **Step 2: The run row** (`ForeverDungeonXPRunTemplate`). Replace `Share` with two
  right-justified `GameFontHighlight` font strings on the title's line:
  - `Rate`: width 62, `TOPRIGHT` at x -8, y -5.
  - `Level`: width 58, its `TOPRIGHT` on `Rate`'s `TOPLEFT`.
  - `Title` ends 6 left of `Level`.

  The template's comment says the headings in `UI/Journal.lua` use the same widths.

- [ ] **Step 3: The window.** `WIDTH = 790`, `LIST_WIDTH = 320` (the spec's 770 and 300 left the
  title 20 short once the Level heading had room for its label and arrow; the run's side keeps its
  451).

- [ ] **Step 4: The headings.** Move `OVERLAP, ROW_LEFT, ROW_RIGHT = 2, 4, 20` above the run
  list's headings so both lists use them. Three headings through `CreateHeading(..., SortRuns)`,
  right to left:
  - `L.COLUMN_RATE`, key `"rate"`, `"RIGHT"`, offset `-(ROW_RIGHT + 8)`; width `62 + ROW_RIGHT`;
    its `BOTTOMRIGHT` on the list's `TOPRIGHT` at 0, -2.
  - `L.COLUMN_LEVEL`, key `"level"`, `"RIGHT"`, offset `-(OVERLAP + 8)`; width `58 + OVERLAP`;
    its `BOTTOMRIGHT` on the rate heading's `BOTTOMLEFT` at `OVERLAP`, 0.
  - `L.COLUMN_DUNGEON`, key `"dungeon"`, as today, ending on the level heading's `BOTTOMLEFT` at
    `OVERLAP`, 0.

  `frame.RunHeadings` holds all three.

- [ ] **Step 5: The rows and the order.** `InitRun` sets `row.Level` to the run's level, or
  `L.NONE` when it isn't a number; `row.Rate` to `Number(data.rate)`, or `L.NONE` without one;
  and the summary with the share in it. `SortRuns` needs no new rule (a first click on `"rate"`
  is descending, as for `"level"`); it logs `ns.log("UI", "sort", key, ascending, "rows", count)`
  under `ns.dev.enabled`. Update the comments that describe the list: the file's header,
  `runSortKey`'s, `RunTitle`'s (the flat list uses the dungeon's name) and `SortRuns`'s.

- [ ] **Step 6: CHANGELOG.** One players' line under `## Unreleased`: the three columns, the
  click on XP/h that ranks every run, and that the share of a level now stands in the line under
  the run.

- [ ] **Step 7: Lint and commit.** `feat(foreverdungeonxp): show level and XP/h columns in the run list`

---

## Step reviewers (Phase 5)

Core: `addon-reviewer`, `api-verifier`, a correctness reviewer and a spec reviewer. Specialist: a
**UI reviewer** (frames, XML, headings). No `savedvariables-guard`: nothing stored, no slash
command, binding or setting changes.

## In-game checks (Phase 6)

No value here can be secret: every number comes from saved runs. The game shows the look.

| Check | How | Expected |
| --- | --- | --- |
| No errors | open the journal, click each heading twice, `/rl`, `scripts/devlog.sh --errors` | clean |
| Sort clicks arrive | `scripts/devlog.sh --addon ForeverDungeonXP --tag UI` | a `sort` line per click with the key and direction |
| Labels over columns | by eye, all three orders | "Level" over the levels, "XP/h" over the rates, arrow inside its heading |
| Flat order is right | click XP/h, select runs top to bottom | the right side's "XP per hour" falls, and equals the row's number |
| Titles fit | "All characters", XP/h order | the name and dungeon readable; only the date cut |
| Window width | by eye | 790 wide sits well; else tune `WIDTH` / `LIST_WIDTH` |

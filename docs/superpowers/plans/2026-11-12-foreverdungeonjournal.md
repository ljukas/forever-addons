# ForeverDungeonJournal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A new addon that records kill XP per creature, per dungeon and per run, and shows it in a
Blizzard-styled journal window opened from a minimap button.

**Architecture:** An event-driven tracker feeds pure logic (message parsing, run rules, formatting)
and writes per-run totals into an account-wide saved table keyed by character. A window built from
Blizzard's `ButtonFrameTemplate`, insets and ScrollBox reads that table. A `Dev/` probe ships first,
because the kill message's wording and the secrecy of creature GUIDs can only be read in game.

**Tech Stack:** Lua 5.1 on the Forever client (Interface 16001, Midnight API), Blizzard
SharedXML templates and ScrollBox, `MenuUtil`, LibStub + CallbackHandler-1.0 + LibDataBroker-1.1 +
LibDBIcon-1.0 via `.pkgmeta` externals, ForeverDev for logging.

**Spec:** `docs/superpowers/specs/2026-11-12-foreverdungeonjournal-design.md`. Read it with this plan.
Process: `docs/feature-workflow.md` (Phases 4-7), conventions: `CLAUDE.md`.

One step, one PR: `feat(foreverdungeonjournal): add a dungeon experience journal`.

## Global Constraints

- Interface `16001`; Lua 5.1; every file starts `local ADDON_NAME, ns = ...`; no globals except
  `ForeverDungeonJournalDB`, `ForeverDungeonJournal_OnAddonCompartmentClick`,
  `SLASH_FOREVERDUNGEONJOURNAL1` and the window's frame name `ForeverDungeonJournalFrame`.
- Never compare, do arithmetic on, concatenate, use as a table key or branch on a value before
  `issecretvalue(v)` says it is not secret. `ns.log` accepts secrets (prints `<secret>`).
- Verify each API in `.cache/wow-ui-source` before first use. Global strings and colour constants
  are not in the cache; declare the ones used in `types/forever.lua` as `---@type string` stubs.
- `ns.log(TAG, ...)`, never `print`. Tags: `LOADED`, `RUN`, `KILL`, `PROBE`, `UI`. Work done only
  to feed a log line goes inside `if ns.dev.enabled then`.
- No custom art. Borders, insets, scroll bars, fonts, highlights and colours come from Blizzard
  templates, font objects and colour constants.
- Only `instanceType == "party"` counts. Quest and exploration XP are never recorded while the
  kill text is readable.
- After every task: `stylua addons template types`, `scripts/lint.sh` clean, then
  `git add <paths>` (never `-A`) with `git branch --show-current` in the same command, one
  conventional commit.
- Player-visible strings live in `Strings.lua` (`ns.L`), plain ASCII.

## Design refinements over the spec (found in Phase 2)

- **Storage is account-wide, keyed by character** (`"Name-Realm"`), the repo's pattern
  (ForeverProfessions); no addon uses `SavedVariablesPerCharacter`. The window shows only the
  current character.
- **`CHAT_MSG_SYSTEM` is `SecretInChatMessagingLockdown`**, so the reset message can't be read
  inside a dungeon. Resets are picked up outside (where the leader usually resets) and from a
  `hooksecurefunc("ResetInstances", ...)` for the player's own reset.
- **`UnitGUID` of an NPC is documented secret "when the unit isn't player-controlled or in the
  party/raid"** while restrictions apply. Expect the copy number to be unreadable at least in
  combat; the fallback rule may be the one that runs in practice. The probe decides.
- **Secret-text mode takes XP from `PLAYER_XP_UPDATE` deltas**, not from a reading at the chat
  event, since the order of the two events is unknown.

## File Structure

```
addons/ForeverDungeonJournal/
  ForeverDungeonJournal.toc   metadata, SavedVariables, load order, compartment func, Dev block
  .pkgmeta                    externals (4 libs under Libs/), ignore Dev, manual changelog
  CHANGELOG.md
  Core.lua                    dev shim, ns.OnInitialize, load + migrate, ns.CharacterKey()
  Strings.lua                 ns.L
  Database.lua                layout comment, DB_VERSION, migrations, run accessors (only file that knows the layout)
  Logic/XPMessage.lua         pure: format string -> matcher, text -> creature, xp
  Logic/RunRules.lua          pure: GUID -> copy number, continue-or-new decision
  Logic/Format.lua            pure: duration, XP per hour, share text
  Tracker.lua                 events: instance entry, kills, XP deltas, death, GUID sources, resets
  Launcher.lua                LDB object + LibDBIcon button, compartment func, /fdj
  UI/Templates.xml            row templates: dungeon header, run row, creature row
  UI/Journal.lua              the window, run list, run detail, delete menu
  Dev/Probe.lua               dev-only: global strings, kill text, GUID secrecy, instance info
.luacheckrc                   globals entry for the addon
types/forever.lua             stubs for global strings / constants LuaLS lacks
```

TOC load order: Libs (LibStub, CallbackHandler-1.0, LibDataBroker-1.1, LibDBIcon-1.0), `Core.lua`,
`Strings.lua`, `Database.lua`, `Logic/*`, `Tracker.lua`, `UI/Templates.xml`, `UI/Journal.lua`,
`Launcher.lua`, then `Dev/Probe.lua` inside `#@do-not-package@`.

## Review Focus

- **Secret values.** `text` of `CHAT_MSG_COMBAT_XP_GAIN`, `UnitGUID`, and anything derived from
  them must pass `issecretvalue` before a compare, pattern match, concatenation or table key.
  Expected: secret text counts a kill under "Unknown creatures" and marks the run approximate;
  a secret GUID is ignored.
- **Level-up mid-run.** XP delta across a ding wraps (`UnitXP` drops, `UnitXPMax` grows). Expected:
  the gain is `(oldMax - oldXP) + newXP`, and the share uses each level's own size.
- **`/reload`, relog and first login inside a dungeon.** Expected: the open run continues, no
  duplicate run, XP baseline re-read so the first delta after reload isn't the whole bar.
- **Run boundaries.** Corpse run continues; walked out alive starts a new run; a copy number read
  later overrides the fallback (empty provisional run discarded). A visit with no kills leaves
  nothing saved.
- **Existing saved data and deletion.** Deleting the selected or the open run must not leave a
  dangling `open` pointer or a selected row that no longer exists; an empty character shows the
  empty state.
- **LibDBIcon on the Forever minimap.** It is untested on this client. If it errors on load, the
  step falls back to a hand-rolled button; that is a design change to raise, not to patch silently.

## Step reviewers (Phase 5)

Core: `addon-reviewer`, `api-verifier`, correctness, spec. Specialists: `savedvariables-guard`
(new SavedVariables, slash command; also the Phase 4 gate after Task 3), UI reviewer (window, XML
templates), release reviewer (`.pkgmeta` externals, TOC do-not-package, nothing dev-only shipped).

## In-game checks

The spec's table, plus:

| Question | Tag | Expected |
| --- | --- | --- |
| Does `PLAYER_XP_UPDATE` fire before or after the kill message? | `PROBE` | an order, logged with both XP readings |
| Does LibDBIcon's button show and drag on Forever's minimap, and does ForeverMinimap's bag take it? | `UI` | no errors in `devlog.sh --errors` |
| Does the window look native (border, insets, scroll bar, highlight)? | none | the user's eyes |

---

### Task 1: Scaffold the addon

**Files:**
- Create: `addons/ForeverDungeonJournal/` via `scripts/new-addon.sh ForeverDungeonJournal`, then
  `ForeverDungeonJournal.toc`, `.pkgmeta`, `Core.lua`, `Strings.lua`, `CHANGELOG.md`
- Modify: `.luacheckrc` (add `files["addons/ForeverDungeonJournal/**"].globals` with the four
  globals from Global Constraints)

**Interfaces:**
- Produces: `ns.OnInitialize(func)`, `ns.CharacterKey() -> "Name-Realm"` (valid from
  `PLAYER_LOGIN`), `ns.L`, `ns.log`, `ns.dev`. Core's load handler sets
  `ForeverDungeonJournalDB = ForeverDungeonJournalDB or {}`, `ns.db`, calls `ns.DB.Migrate(ns.db)`
  then the initializers (copy `addons/ForeverProfessions/Core.lua:111-129`).

- [ ] **Step 1:** Run the scaffold script. TOC: `## Notes: Records the experience you gain from
  kills in each dungeon run.`, `## IconTexture: Interface\Icons\INV_Misc_Book_09` (verify the
  icon exists in Blizzard's own usage or pick one that does), `## X-Category: Dungeons`,
  `## SavedVariables: ForeverDungeonJournalDB`,
  `## AddonCompartmentFunc: ForeverDungeonJournal_OnAddonCompartmentClick`.
- [ ] **Step 2:** `.pkgmeta` like `addons/ForeverUnitFrames/.pkgmeta`: four externals under
  `Libs/` in the long form (`url:` + `tag:`). Find each library's git URL and its latest release
  tag with `git ls-remote --tags <url>`; pin the tag. `ignore: - Dev`. Run `scripts/libs.sh`,
  then list each lib's load file in the TOC (LibStub first).
- [ ] **Step 3:** `CHANGELOG.md` under `## Unreleased`: `- A journal of your dungeon runs: kill
  experience per run and per creature, its share of a level, kills, time and experience per
  hour. Open it from the minimap button or with /fdj.`
- [ ] **Step 4:** `scripts/lint.sh` clean (Database.lua doesn't exist yet: keep Core's
  `ns.DB.Migrate` call for Task 3 and make this commit load without it). Commit:
  `feat(foreverdungeonjournal): scaffold the addon`.

### Task 2: The probe, then a checkpoint with the user

**Files:**
- Create: `addons/ForeverDungeonJournal/Dev/Probe.lua` (TOC: inside `#@do-not-package@`)

**Interfaces:**
- Produces: devlog lines only. Starts with `if not ns.dev.enabled then return end`.

- [ ] **Step 1:** On `PLAYER_LOGIN`, log once (tag `PROBE`, `strings <name> <value>`) every
  string global whose name starts with `COMBATLOG_XPGAIN` or contains `INSTANCE_RESET` or
  `XP_GAIN`, iterating `_G` with `type(k) == "string" and type(v) == "string"`.
- [ ] **Step 2:** Log, each with `ForeverDev.Situation(unit)`:
  - `CHAT_MSG_COMBAT_XP_GAIN`: `text` (ForeverDev prints `<secret>`), `ForeverDev.SecretNames`
    over text/playerName/guid, and `UnitXP`/`UnitXPMax("player")` at that moment.
  - `PLAYER_XP_UPDATE`: `UnitXP`/`UnitXPMax` (gives the event order against the line above).
  - `PLAYER_ENTERING_WORLD`: both flags and every `GetInstanceInfo()` return.
  - `PLAYER_TARGET_CHANGED`, `UPDATE_MOUSEOVER_UNIT`, `NAME_PLATE_UNIT_ADDED` for an attackable
    NPC: `C_Secrets.ShouldUnitIdentityBeSecret(unit)`, and `UnitGUID(unit)` through
    `ForeverDev.Describe`. Use `LogChanged`/`LogOnce` keyed by situation so nameplates don't
    flood the log (never pass a secret as `LogChanged`'s value).
  - `CHAT_MSG_SYSTEM`: the text, only when not secret, only lines containing the word "reset"
    (after the secret check).
  - `PLAYER_DEAD`, `PLAYER_UNGHOST`: `UnitIsDeadOrGhost`, `UnitIsGhost`, `IsInInstance()`.
- [ ] **Step 3:** Lint, commit `feat(foreverdungeonjournal): probe the kill message and creature ids`.
- [ ] **Step 4 (checkpoint, stop here):** `scripts/worktree.sh status` to confirm the game loads
  the addon from this worktree. Ask the user to: restart the client (new addon folder), kill two
  creatures in the open world (one rested if possible), enter a dungeon, target a creature out of
  combat, kill a pack, die or walk out and back in if convenient, then `/rl`. Read
  `scripts/devlog.sh --addon ForeverDungeonJournal --tag PROBE`. Record the answers in the spec's
  "What the client gives us" section (dated, "confirmed in game"), and tell the user which paths
  are real before continuing. If the user can't reach a dungeon now, continue with the open-world
  answers and keep the dungeon questions as in-game checks.

### Task 3: Saved data (SavedVariables gate)

**Files:**
- Create: `addons/ForeverDungeonJournal/Database.lua`

**Interfaces:**
- Produces (the only file that reads or writes the layout):
  - `ns.DB.Migrate(db)`; `DB_VERSION = 1`; migration 1 creates `db.characters` and `db.minimap`
    with the defensive `type(x) ~= "table"` form (`addons/ForeverUnitFrames/Database.lua:16-30`).
  - `ns.DB.Character() -> character` (creates `{ runs = {}, open = {}, nextID = 1 }` for
    `ns.CharacterKey()`).
  - `ns.DB.NewRun(instanceID, name, level, openedBy) -> run`; numbers it one above that
    dungeon's highest `number`; sets `character.open[instanceID] = run.id`.
  - `ns.DB.OpenRun(instanceID) -> run|nil`; `ns.DB.CloseRun(instanceID)`;
    `ns.DB.CloseAllRuns()`; `ns.DB.ReopenRun(run)`.
  - `ns.DB.AddKill(run, creatureName|nil, xp, share, now)`; `nil` name means the
    `ns.L.UNKNOWN_CREATURES` bucket (stored under a fixed key `"?"`, not the localized string)
    and sets `run.approximate = true`.
  - `ns.DB.AddXP(run, xp, share)` (secret mode: XP arrives apart from the kill).
  - `ns.DB.DeleteRun(id)`; `ns.DB.Runs() -> array` (the character's runs, storage order);
    `ns.DB.RunByID(id)`; `ns.DB.Minimap() -> db.minimap` (LibDBIcon's table).
- Layout, documented in the file's header comment:

```
ForeverDungeonJournalDB (account-wide)
  version    = schema version
  minimap    = LibDBIcon's table ({ hide, minimapPos, ... })
  characters = { ["Name-Realm"] = {
    nextID = n, open = { [instanceID] = runID },
    runs = { { id, instanceID, name, number, copy = string|nil, openedBy = "first"|"copy"|"alive"|"reset"|"gap",
               level, firstKill, lastKill,           -- GetServerTime(); nil until the first kill
               xp, share, kills, parsed, fallback,   -- share is a fraction of a level, summed
               approximate = true|nil, died = true|nil,
               creatures = { [name] = { kills, xp } } }, ... } } }
```

- [ ] **Step 1:** Write the file. A run with `kills == 0` is saved only while it is open; add
  `ns.DB.DropEmptyRun(run)` which removes it and its `open` pointer (Tracker calls it on leaving).
- [ ] **Step 2:** Lint, commit `feat(foreverdungeonjournal): store runs per character`.
- [ ] **Step 3 (gate):** dispatch `savedvariables-guard` on this commit; fix or rule on every
  finding before Task 4.

### Task 4: Pure logic

**Files:**
- Create: `Logic/XPMessage.lua`, `Logic/RunRules.lua`, `Logic/Format.lua`

**Interfaces:**
- `ns.XPMessage.Pattern(formatString) -> pattern, order`: escapes Lua magic characters, turns
  `%s` into `(.+)` and `%d` into `(%d+)`, handles positional `%1$s`/`%2$d` (order maps captures
  to argument positions), anchors with `^...$`.
- `ns.XPMessage.Build(strings) -> matchers`: `strings` is a list of
  `{ format = <global string value>, creature = <arg index>, xp = <arg index> }`, one per
  creature-kill variant the Task 2 probe found (plain, rested, group, penalty...). Sorted longest
  format first so a bonus variant isn't swallowed by the plain one.
- `ns.XPMessage.Parse(matchers, text) -> creatureName, xp | nil`: first matcher that matches;
  `xp` as a number. Returns nil for text that names no creature. The caller guarantees `text`
  is not secret.
- `ns.RunRules.Copy(guid) -> string|nil`: for a non-secret `Creature-`/`Vehicle-` GUID, the fifth
  `-`-separated field (`zoneUID`); nil for anything else.
- `ns.RunRules.Decide(open, entry) -> "continue"|"new", reason`, with
  `open = { copy, died, lastKill } | nil` and
  `entry = { copy = string|nil, reload = bool, now = number }`, in this order:
  1. no open run -> `"new", "first"`
  2. both copies known -> equal: `"continue", "copy"`; different: `"new", "copy"`
  3. `entry.reload` -> `"continue", "reload"`
  4. `open.lastKill` and `now - open.lastKill > 1800` -> `"new", "gap"`
  5. `open.died` -> `"continue", "died"`
  6. otherwise -> `"new", "alive"`
- `ns.Format.Duration(seconds) -> "38 min"` (`"< 1 min"` under 60, `"1 h 12 min"` from 3600);
  `ns.Format.PerHour(xp, seconds) -> number|nil` (nil under 60 seconds);
  `ns.Format.Share(fraction) -> "41%"` (whole percent; `"< 1%"` for a non-zero value under 0.005).

- [ ] **Step 1:** Write the three files with a comment block of worked examples above each
  function (the repo has no test runner; a reviewer checks these by reading). Include: a format
  with a trailing bonus clause, a positional format, a creature name containing `-` and `'`,
  a `Player-` GUID (nil), each `Decide` branch.
- [ ] **Step 2:** Lint, commit `feat(foreverdungeonjournal): parse kill messages and decide runs`.

### Task 5: The tracker

**Files:**
- Create: `Tracker.lua`
- Modify: `types/forever.lua` (stubs for the global strings Task 2 found)

**Interfaces:**
- Consumes: `ns.DB.*`, `ns.XPMessage.*`, `ns.RunRules.*`.
- Produces: `ns.Tracker.CurrentRun() -> run|nil` (the run being recorded, nil outside a party
  instance); fires `EventRegistry:TriggerEvent("ForeverDungeonJournal.RunsChanged")` after any
  change to saved runs.

- [ ] **Step 1: Entry and exit.** On `PLAYER_ENTERING_WORLD(isInitialLogin, isReloadingUi)`:
  read `GetInstanceInfo()`. In a party instance: try a copy number (Step 3), call
  `RunRules.Decide`, then continue or `NewRun` (`openedBy` = reason), clear `run.died`, set the
  XP baseline (`UnitXP`, `UnitXPMax`). Not in one: `DropEmptyRun` the run that was current, clear
  current. Log `RUN <enter|leave> <name> <instanceID> <decision> <reason> copy=<copy>`.
- [ ] **Step 2: Kills.** On `CHAT_MSG_COMBAT_XP_GAIN(text)` with a current run:
  - text not secret: `Parse`; on a hit `AddKill(run, name, xp, xp / UnitXPMax("player"), GetServerTime())`,
    `parsed + 1`; on a miss log `KILL unparsed <text>` and ignore.
  - text secret: `AddKill(run, nil, 0, 0, now)`, `fallback + 1`, and switch the run to
    delta mode: every `PLAYER_XP_UPDATE("player")` adds `AddXP(run, delta, delta / maxAtGain)`
    where `delta` is `new - old`, or `(oldMax - old) + new` when `new < old`.
  - Always refresh the XP baseline on `PLAYER_XP_UPDATE`. Clear `run.died` on a recorded kill.
  - Build the matchers once, at initialize, from the global strings the probe found; a missing
    global is skipped, and with none found every text counts as unparsed (logged once).
- [ ] **Step 3: Copy number.** On `PLAYER_TARGET_CHANGED`, `UPDATE_MOUSEOVER_UNIT`,
  `NAME_PLATE_UNIT_ADDED(unit)`, while the current run has no copy for this visit: if
  `UnitExists(unit)` and `UnitCanAttack("player", unit)`, read `UnitGUID(unit)`; skip when nil or
  `issecretvalue`. With a copy `c`: run has no copy -> if another run of this dungeon has copy `c`
  and the current run has no kills, `DeleteRun(current)`, `ReopenRun(that)`; else stamp
  `run.copy = c`. Run has a different copy -> `NewRun(..., "copy")` with `copy = c`. Stop
  listening once known; start again on the next entry. Log `RUN copy <same|new|stamp> <c>`.
- [ ] **Step 4: Death and resets.** `PLAYER_DEAD` with a current run: `run.died = true`.
  `hooksecurefunc("ResetInstances", ...)`: `CloseAllRuns()`, log `RUN reset own`.
  `CHAT_MSG_SYSTEM(text)` when not secret and matching the reset format string from the probe
  (dungeon name captured): close the open run whose `name` equals it, log `RUN reset <name>`.
  If the probe found no such string, leave this handler out and say so in the PR.
- [ ] **Step 5:** Lint, commit `feat(foreverdungeonjournal): record kills into runs`.

### Task 6: The journal window

**Files:**
- Create: `UI/Templates.xml`, `UI/Journal.lua`
- Modify: `Strings.lua`

**Interfaces:**
- Consumes: `ns.DB.Runs/RunByID/DeleteRun`, `ns.Tracker.CurrentRun`, `ns.Format.*`,
  the `ForeverDungeonJournal.RunsChanged` event.
- Produces: `ns.Journal.Toggle()`.

- [ ] **Step 1: Frame.** Created on first `Toggle()`: `CreateFrame("Frame",
  "ForeverDungeonJournalFrame", UIParent, "ButtonFrameTemplate")`, `ButtonFrameTemplate_HidePortrait`,
  `ButtonFrameTemplate_HideButtonBar`, `:SetTitle(ns.L.TITLE)`, about 700x460, centred,
  `tinsert(UISpecialFrames, "ForeverDungeonJournalFrame")`, shown and hidden with plain
  `Show()`/`Hide()` (no `UIPanelWindows`, so it opens in combat). Movable by dragging the title
  bar; position not saved. The template's `Inset` is re-anchored as the left list (about 250
  wide); a second `InsetFrameTemplate` frame is the right detail pane.
- [ ] **Step 2: Run list.** `WowScrollBoxList` + `MinimalScrollBar`,
  `CreateScrollBoxListLinearView`, `SetElementFactory` choosing a header or run-row template from
  `UI/Templates.xml` (pattern: `Blizzard_UIPanels_Game/Camelot/SkillsFrame.lua:87-124`). Data
  built by a pure local function from `ns.DB.Runs()`: dungeons ordered by their newest run,
  runs newest first; header `"<name> - N runs"`; row line 1 `"Run N - <date>"` with the share
  right-aligned, line 2 `"7,380 XP - 96 kills - 38 min"`. Hover:
  `Interface\Buttons\UI-Common-MouseHilight` (ADD); selected:
  `Interface\FriendsFrame\UI-FriendsFrame-HighlightBar` (as `Camelot/PaperDollFrame.xml:192`).
  Fonts `GameFontNormal` (headers, run title), `GameFontHighlightSmall` (line 2).
  Left click selects; right click opens `MenuUtil.CreateContextMenu` with `ns.L.DELETE_RUN`.
- [ ] **Step 3: Detail.** Header line `"<name> - run N - level L"`, plus `ns.L.APPROXIMATE` in
  `GRAY_FONT_COLOR` when `run.approximate`. Five label/value pairs in a row (labels
  `GameFontNormalSmall`, values `GameFontHighlightLarge`): kill XP, share, kills, time, XP per
  hour (`"-"` when `PerHour` is nil). Numbers through `BreakUpLargeNumbers`. Below, a column
  header row and a second ScrollBox of creature rows (Creature, Kills, XP each, Total), sorted by
  total XP descending; the `"?"` bucket shows as `ns.L.UNKNOWN_CREATURES`, last.
- [ ] **Step 4: State.** On show and on `RunsChanged` while shown: rebuild the list; keep the
  selection if its run still exists, else select `ns.Tracker.CurrentRun()` or the newest run.
  With no runs: empty list, detail pane hidden, `ns.L.EMPTY` ("Run a dungeon to start your
  journal.") centred in `GameFontDisable`. Log `UI show runs=<n>`.
- [ ] **Step 5:** Lint, commit `feat(foreverdungeonjournal): show runs in a journal window`.

### Task 7: Minimap button, compartment entry, slash command

**Files:**
- Create: `Launcher.lua`

**Interfaces:**
- Consumes: `ns.Journal.Toggle`, `ns.DB.Minimap()`.

- [ ] **Step 1:** In an initializer: a LibDataBroker launcher object (`type = "launcher"`, icon =
  the TOC's `IconTexture`, `OnClick` toggles on left click, `OnTooltipShow` adds the title and
  "Click to open"), registered with LibDBIcon against `ns.DB.Minimap()`. Fetch both with
  `LibStub(name, true)` and skip the button (log `UI nolib`) if either is nil.
- [ ] **Step 2:** `function ForeverDungeonJournal_OnAddonCompartmentClick() ns.Journal.Toggle() end`;
  `SLASH_FOREVERDUNGEONJOURNAL1 = "/fdj"` with the same action.
- [ ] **Step 3:** Lint, commit `feat(foreverdungeonjournal): open the journal from the minimap`.

### Task 8: Review, verify, ship (workflow Phases 5-7)

- [ ] **Step 1:** `git fetch origin`; dispatch the step reviewers above in one message over
  `git diff origin/main...HEAD`, each given this plan, the spec and Review Focus, told to assume
  the step is wrong. Verify each finding, fix confirmed ones one commit per concern.
- [ ] **Step 2:** Pre-PR gate (`docs/feature-workflow.md`), then in game: a full dungeon run with
  a corpse run or a walk-out, `/rl`, `scripts/devlog.sh --errors` clean, and the in-game check
  tables answered from `--addon ForeverDungeonJournal`. Unanswered checks go in a
  `foreverdungeonjournal-launch-checks` memory and the PR says so.
- [ ] **Step 3:** Open the PR with the template; `scripts/worktree.sh restore` before the
  worktree is removed.

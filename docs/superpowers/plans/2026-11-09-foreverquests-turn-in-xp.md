# ForeverQuests turn-in XP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A new addon, ForeverQuests, that shows on the exp bar (fill, pip and tooltip lines)
where the player's XP lands after turning in every completed quest in the log.

**Architecture:** `Quests.lua` collects the completed quests and their reward XP, and
`Projection.lua` turns XP numbers into a pure result table. `ExpBar.lua` draws the fill and the
pip on each of Blizzard's exp bar instances and appends the tooltip lines. Each layer only
reads from the one before it.

**Tech Stack:** Lua 5.1 on the Forever client (interface 16001), Blizzard_StatusTrackingBar
hooks. There is no test framework: the pure logic is checked by reading, the rest by
`scripts/lint.sh` and in game.

**Spec:** `docs/superpowers/specs/2026-11-09-foreverquests-turn-in-xp-design.md`

## Global Constraints

- One PR: `feat(foreverquests): show turn-in XP on the experience bar`.
- No SavedVariables, no options panel, no slash command (spec, Non-goals).
- Hook only: `HookScript` / `hooksecurefunc`, no replacing Blizzard functions or fields.
- Never do arithmetic on, compare or branch on a value for which `issecretvalue(v)` is true.
- TOC `## Category: Forever Enhanced Addons`, `## X-Category: Quests`, interface 16001.
- Strings: `Completed quests: %d (+%s XP)`, `→ %d%% of level %d`, `Level up!`,
  `+%s XP past level %d`, `Loading quest rewards…`. Numbers go through `BreakUpLargeNumbers`.
- Colours come from Blizzard constants (`GREEN_FONT_COLOR`, `GRAY_FONT_COLOR`, ...), never
  hard-coded RGB.

## Review Focus

1. **Load order.** `MainStatusTrackingBarContainer` may not exist yet when ForeverQuests loads.
   Hook through `EventUtil.ContinueOnAddOnLoaded("Blizzard_StatusTrackingBar", ...)`, which
   runs at once if it is already loaded (Task 2).
2. **Secret values in combat.** Quest XP or `UnitXP` turning secret mid-combat must give the
   count-only result, not a Lua error (Task 1: `Collect`, Task 2: `Refresh`).
3. **A quest completes after login and its reward isn't loaded.** Show the pending state, then
   the fill once `QUEST_DATA_LOAD_RESULT` arrives, with no `/reload` (Task 1).
4. **Bar width changes** (gamepad mode, edit mode, UI scale). The fill and the pip follow the
   bar's width (`OnSizeChanged`), so they never use a stale width (Task 2).
5. **Hovering the rested pip** shows our lines too, and the lines are never added twice to one
   tooltip (Task 3).

---

### Task 1: Scaffold, quest collection and projection

**Files:**
- Create (via `scripts/new-addon.sh ForeverQuests`, then edit): `addons/ForeverQuests/ForeverQuests.toc`,
  `Core.lua`, `CHANGELOG.md`
- Create: `addons/ForeverQuests/.pkgmeta` (copy ForeverActionBars', `package-as: ForeverQuests`)
- Create: `addons/ForeverQuests/Quests.lua`, `addons/ForeverQuests/Projection.lua`

**Interfaces:**
- Produces: `ns.Quests.Collect() -> { count = n, xp = n, pending = bool, secret = bool }`.
  `count` is the number of completed quests that aren't headers or hidden. `xp` is the sum of
  `GetQuestLogRewardXP(questID)` over them. `pending` is true if any of them is missing
  `HaveQuestRewardData(questID)`, in which case `RequestLoadQuestByID` is called once for it.
  `secret` is true if any XP value read is secret. When `pending` or `secret` is true, `xp`
  is 0.
- Produces: `ns.Project(curXP, maxXP, level, gain) -> { levelsUp = bool, fraction = 0..1,
  percent = int, nextLevel = int, overflow = n }`. When `cur + gain >= maxXP`: `levelsUp`
  is true, `fraction = 1`, `overflow = cur + gain - maxXP` and `nextLevel = level + 1`.
  Otherwise `fraction = (cur + gain) / maxXP`, `percent = floor(fraction * 100)` and
  `nextLevel = level`. `Project` is pure: no API calls.
- Produces: `ns.OnQuestsChanged`, a `CallbackRegistry`-free hook. Set it to one function that
  Task 2 assigns; `Quests.lua` calls it (if set) on `QUEST_LOG_UPDATE`, `QUEST_DATA_LOAD_RESULT`,
  `PLAYER_XP_UPDATE`, `PLAYER_LEVEL_UP` and `PLAYER_ENTERING_WORLD`, at most once per frame
  (coalesce with `C_Timer.After(0, ...)`).

- [ ] **Step 1:** `scripts/new-addon.sh ForeverQuests`. Remove `## SavedVariables` from the TOC and
  the DB lines from `Core.lua`. Set `## Notes: Shows on the experience bar where your XP lands
  after turning in your completed quests.` and `## X-Category: Quests`. Add the tags comment to the
  shim: `-- Tags: XP (Quests.lua), TURNIN (Quests.lua), BAR (ExpBar.lua).` TOC file order:
  `Core.lua`, `Projection.lua`, `Quests.lua`, `ExpBar.lua` (the last is added in Task 2).
- [ ] **Step 2:** Write `Projection.lua` (`ns.Project`) and `Quests.lua` (`ns.Quests.Collect`, the
  event frame). Instrumentation, inside `if ns.dev.enabled then`: on each collection,
  `ns.dev:LogChanged("collect", <count..xp..pending..secret>, "XP", ...)` with each quest's
  ID, its XP and `issecretvalue` of the XP and of `UnitXP`. On `QUEST_TURNED_IN(questID,
  xpReward)`, `ns.log("TURNIN", questID, xpReward, <the XP predicted for that quest>)`, which
  needs `Collect` to keep the last per-quest XP map in a local.
- [ ] **Step 3:** `scripts/lint.sh`. Expected: clean.
- [ ] **Step 4:** Commit:
  `feat(foreverquests): collect completed quests' reward XP` (TOC, Core, Projection, Quests,
  .pkgmeta, CHANGELOG).

### Task 2: Turn-in fill and pip on the exp bar

**Files:**
- Create: `addons/ForeverQuests/ExpBar.lua` (and list it in the TOC)

**Interfaces:**
- Consumes: `ns.Quests.Collect`, `ns.Project`, `ns.OnQuestsChanged`.
- Produces: `ns.ExpBar.lastResult` (the latest `{ quests = Collect(), proj = Project(...) or nil }`),
  read by Task 3's tooltip.

- [ ] **Step 1:** On `Blizzard_StatusTrackingBar` loaded, for each of
  `MainStatusTrackingBarContainer` and `SecondaryStatusTrackingBarContainer` take
  `.bars[StatusTrackingBarInfo.BarsEnum.Experience]` and add, as children of that bar:
  - a texture `fill` with atlas `UI-HUD-ExperienceBar-Fill-Prediction`, layer ARTWORK, sublevel 0
    (above Blizzard's rested fill at -1), height = bar height, `SetVertexColor` from
    `QUEST_OBJECTIVE_FONT_COLOR`, or when it levels up from `GREEN_FONT_COLOR`;
  - a texture `pip` with atlas `UI-HUD-ExperienceBar-Frame-Pip`, size 10×14, on an overlay frame
    one level above the bar so it draws over the XP fill.
- [ ] **Step 2:** `Refresh()` for every hooked bar: hide both if `IsXPUserDisabled()`,
  `GameRulesUtil.IsPlayerAtEffectiveMaxLevel()`, the quest result has `count == 0`, `pending`,
  `secret`, `xp == 0`, or `UnitXP`/`UnitXPMax` is secret. Otherwise `proj = ns.Project(...)`;
  the fill spans from `cur / max * width` to `proj.fraction * width` (left edge anchored at
  `LEFT, cur/max*width`, width = the difference, `SetTexCoord` matching the span), and the pip
  is centred at the right end and hidden when `proj.levelsUp`, or when the fraction is above 0.99
  (Blizzard's `hideAtBarEdge`). Store `ns.ExpBar.lastResult`. `ns.OnQuestsChanged = Refresh`;
  also `HookScript("OnSizeChanged", Refresh)` and `HookScript("OnShow", Refresh)` on each bar.
  `ns.dev:LogChanged("bar", fraction, "BAR", cur, max, gain, fraction, levelsUp)`.
- [ ] **Step 3:** `scripts/lint.sh`. Expected: clean.
- [ ] **Step 4:** Commit `feat(foreverquests): draw the turn-in XP fill on the experience bar`.

### Task 3: Tooltip lines and changelog

**Files:**
- Modify: `addons/ForeverQuests/ExpBar.lua`
- Modify: `addons/ForeverQuests/CHANGELOG.md`

**Interfaces:**
- Consumes: `ns.ExpBar.lastResult`, `ns.Quests.Collect` (refresh it on hover, so it's current).

- [ ] **Step 1:** `AddTooltipLines(owner)`: run `Refresh()`; with `count == 0` add nothing. Otherwise
  `tooltip = GetAppropriateTooltip()`; if it isn't shown or isn't owned by this bar's area, open
  it as Blizzard does (`GameTooltip_SetDefaultAnchor(tooltip, UIParent)`, title
  `XP_TEXT:format(BreakUpLargeNumbers(cur), BreakUpLargeNumbers(max), percent)`). Add a blank line
  (`GameTooltip_AddBlankLineToTooltip`) and then:
  - pending: `Completed quests: N` (normal), `Loading quest rewards…` (`GRAY_FONT_COLOR`);
  - secret: `Completed quests: N` only;
  - otherwise: `Completed quests: N (+X XP)` (normal), then either `→ P% of level L`
    (highlight) or `Level up!` and `+X XP past level L+1` (`GREEN_FONT_COLOR`).
  Then `tooltip:Show()`. Guard against adding twice: remember the tooltip and a counter that
  `OnHide`/`OnTooltipCleared` resets.
- [ ] **Step 2:** `bar:HookScript("OnEnter", AddTooltipLines)` and
  `bar.ExhaustionTick:HookScript("OnEnter", AddTooltipLines)` on each hooked bar.
- [ ] **Step 3:** CHANGELOG `## Unreleased`: `- New addon. The experience bar shows where your XP
  lands after turning in your completed quests, and its tooltip says whether that's a level up.`
- [ ] **Step 4:** `stylua addons` then `scripts/lint.sh`. Expected: clean.
- [ ] **Step 5:** Commit `feat(foreverquests): explain turn-in XP in the experience bar tooltip`.

## Step reviewers (Phase 5)

Core: `addon-reviewer`, `api-verifier`, correctness and spec reviewers. Specialists: **UI
reviewer** (hooks into Blizzard UI, atlases, layering) and **release reviewer** (new TOC and
`.pkgmeta`).

## In-game checks

| # | Check | Evidence |
|---|---|---|
| 1 | Quest XP, `UnitXP` and `UnitXPMax` aren't secret, in or out of combat | `devlog.sh --tag XP`: secret flags false |
| 2 | Predicted XP equals the XP given | `devlog.sh --tag TURNIN`: `xpReward` = prediction |
| 3 | Fill over the rested overlay, under the XP fill; the pip lines up; the level-up tint reads | by eye, screenshot |
| 4 | Fill appears on completion, goes on turn-in or abandon, without `/reload` | `devlog.sh --tag BAR` changes, by eye |
| 5 | The tooltip shows the lines from the bar and from the rested pip, once | by eye |

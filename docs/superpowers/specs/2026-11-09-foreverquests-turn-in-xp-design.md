# ForeverQuests: turn-in XP on the experience bar

Date: 2026-11-09 · Status: approved · Addon: ForeverQuests (new)

## Intent

When you have quests marked complete in your log, you want to know at a glance whether turning
them all in gets you a level, without opening the log or adding up rewards. The exp bar is
where you look for that, so the answer goes there: a fill showing where your XP lands after the
turn-ins, and a tooltip that spells it out.

## Goals

1. **Turn-in fill on the exp bar.** When the log holds completed quests that reward XP, a fill
   runs from the current XP to where the XP lands after turning them all in, ending in a pip.
   It is drawn like Blizzard's rested overlay (`ExhaustionLevelFillBar` with the
   `UI-HUD-ExperienceBar-Fill-Prediction` atlas, and the `UI-HUD-ExperienceBar-Frame-Pip` atlas
   for the pip), tinted so it can't be mistaken for rested XP.
2. **Level-up is unmistakable** *(my call, the user didn't pick)*. If the turn-ins reach or pass
   the next level, the fill runs to the bar's right end and switches to a distinct tint, and the
   pip is hidden (as Blizzard hides the rested pip at the bar edge). The tooltip's result line
   turns green.
3. **Tooltip lines.** Hovering the exp bar shows Blizzard's tooltip as today, followed by:
   - `Completed quests: N (+X XP)`. X is formatted with `BreakUpLargeNumbers`.
   - The result: `→ 82% of level 23`, or when it levels, in green, `Level up!` followed by
     `+1,234 XP past level 24`. *(My call.)* The wording stays true when the turn-ins cover more
     than one level, which happens at low levels: the client doesn't say what level 24 needs, so
     the addon never claims you land *in* level 24, only that you get at least that far.
   - While some completed quests' reward data is still loading, the tooltip shows
     `Completed quests: N` and a grey `Loading quest rewards…` line, and no fill is drawn until
     every reward has loaded. *(My call: all or nothing, never a partial total.)*
4. **Nothing to show, nothing drawn.** With no completed quests (or none rewarding XP), there is
   no fill, no pip and no extra tooltip lines. The same applies at max level, with XP gain
   disabled (`IsXPUserDisabled`), and whenever Blizzard isn't showing the exp bar.
5. **Stays current.** The fill and tooltip update when quests complete, are turned in or
   abandoned, when XP changes or you level, and on login and `/reload`.

## Non-goals

- No quest list, no per-quest breakdown in the tooltip (first slice; can come later).
- No new window, no options panel, no slash command, no SavedVariables in this slice.
- No exact landing point beyond one level up. A single client API only gives the XP needed for
  the *current* level (`UnitXPMax`), so beyond the next level the tooltip says how much XP
  carries into the next level, not a percentage of it. No hard-coded XP-per-level table.
- Rested XP doesn't apply to quest rewards and isn't factored in.

## Anti-goals

- Taint: no replacing Blizzard functions or frame fields; hook only (`HookScript`,
  `hooksecurefunc`).
- A number that's wrong without saying so. If quest XP can't be read (secret, or reward data
  not loaded yet), don't draw a guess.

## Which quests count

Every quest log entry that isn't a header or hidden, for which `C_QuestLog.IsComplete(questID)`
(or `ReadyForTurnIn`) is true. Its XP is `GetQuestLogRewardXP(questID)`: the reward at the
player's current level, as Blizzard shows it in the quest log. This is a legacy global that
isn't in the generated API docs, but Blizzard's own Forever UI calls it (e.g.
`Blizzard_FrameXMLUtil/Mainline/QuestUtils.lua`), so it exists. Reward data may not be loaded
for every quest yet; the builder handles that the way Blizzard does (`HaveQuestRewardData`,
`C_QuestLog.RequestLoadQuestByID` and the load-result event, verified in the Forever source).

## Where it hooks

- Exp bar instances: `MainStatusTrackingBarContainer.bars[StatusTrackingBarInfo.BarsEnum.Experience]`
  and the same on `SecondaryStatusTrackingBarContainer` (built in
  `Blizzard_StatusTrackingBar/Mainline/StatusTrackingManagerOverrides.lua`, `InitializeBars`).
  Hook both. Position the fill and pip as a fraction of the bar's width, the way
  `ExhaustionTickMixin:UpdateTickPosition` does (`Shared/ExpBar.lua`), and follow resizes
  (gamepad width, edit mode).
- Tooltip: the bar's `OnEnter` builds its tooltip in `ExhaustionTick:ExhaustionToolTipText()`,
  which returns *without showing a tooltip* when there's no rest state. Post-hook `OnEnter`
  and also the rested pip's own `OnEnter` (hovering the pip calls `ExhaustionToolTipText`
  directly). If the tooltip isn't shown, open it as Blizzard does (`GetAppropriateTooltip()`,
  `GameTooltip_SetDefaultAnchor`, title `XP_TEXT`), append the lines, then `Show()` again.
- Layering: the turn-in fill must be visible over the rested overlay and must not cover the
  current-XP fill. Settled in game (in-game check 3).

## Secret values

- If `GetQuestLogRewardXP`, `UnitXP` or `UnitXPMax` returns a secret value (`issecretvalue`),
  no arithmetic is done: no fill, and the tooltip shows `Completed quests: N` only.
- Quest log flags (`IsComplete`) are documented `SecretArguments = "AllowedWhenUntainted"`;
  passing a plain questID is fine.

## Addon

A new addon `ForeverQuests` from `template/Addon` (`scripts/new-addon.sh`), category
`Forever Enhanced Addons`, `## X-Category: Quests`. It gives later quest features a home
*(my call; the user accepted it)*.

## In-game checks (instrumented with `ns.log`)

1. **XP is readable.** `GetQuestLogRewardXP`, `UnitXP` and `UnitXPMax` aren't secret, in or out
   of combat. Tag `XP` logs each quest's ID, completion and XP, and the secret flags.
2. **Totals match.** The tooltip's +X equals the XP actually gained after turning them in
   (`QUEST_TURNED_IN` reports the XP; tag `TURNIN` logs it next to our prediction).
3. **Looks right.** The fill sits over the rested overlay, under the XP fill; the pip lines up;
   the level-up tint reads clearly. Checked by eye.
4. **Updates.** The fill appears when an objective completes and goes when the quest is turned
   in or abandoned, without a `/reload`.

## Left to the builder

Exact tint colours (from Blizzard's colour constants), the file split, event throttling, and
how reward-data loading is retried.

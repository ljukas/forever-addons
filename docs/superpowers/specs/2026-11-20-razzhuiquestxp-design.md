# RazzhUIQuestXP: turn-in XP as a line of text

Date: 2026-11-20 · Status: approved · Addon: RazzhUIQuestXP (new module)

## Intent

With completed quests in the log, the player wants to know at a glance what turning them all in
is worth: how much XP, and how much of the current level that is. ForeverQuests drew this on
Blizzard's exp bar (spec `2026-11-09-foreverquests-turn-in-xp-design.md`) and was removed when the
user moved to EllesmereUI, which replaces that bar. This version is one line of text of its own,
bound to no Blizzard frame, placed in Edit Mode.

## Goals

1. **One line.** `Quests: +4,250 XP (31%)`: the summed XP of every completed quest in the log, and
   that sum as a share of the whole current level (`floor(xp * 100 / UnitXPMax)`, so it can pass
   100%). The line is gold (`NORMAL_FONT_COLOR`), and green (`GREEN_FONT_COLOR`) when current XP
   plus the turn-ins reaches the next level. *(Wording and colours are my call; the user approved
   them.)*
2. **Wordy tooltip on hover.** Title `Quest turn-ins`, then:
   - `Completed quests: N (+X XP)`
   - `That is P% of level L (M XP).`
   - grey `Includes +3% from Well-Rested` when an XP buff applies
   - `Ends at 82% of level 23`, or green `Level up!` and `+1,234 XP past level 24`
3. **Placed in Edit Mode.** The line is an Edit Mode box (LibEditMode, as ForeverCombatText and
   RazzhUIResourceBars): drag to place it, and a **Font Size** slider in its dialog (the user asked
   for this). Position and font size are kept per Edit Mode layout.
4. **Nothing to show, nothing drawn.** The line is hidden with no completed quests, none rewarding
   XP, at max level, with XP gain disabled, while reward data is still loading (all or nothing, at
   most 5 seconds), and when a value it needs is secret. While Edit Mode is open it always shows:
   the real line if there is one, else the sample `Quests: +4,250 XP (31%)`.
5. **Stays current** on quest, XP, level and XP-buff changes, on login and `/reload`.
6. **Options page** under RazzhUI with one button that opens Edit Mode, as the other two Edit Mode
   modules have.

## Non-goals

- No per-quest breakdown, no colour or font-face options, no slash command.
- No exact landing point beyond one level up (the client only gives the current level's XP need).
- Rested XP isn't factored in: it doesn't apply to quest rewards.

## Anti-goals

- A number that is wrong without saying so: a secret or unloaded reward means no line, not a
  partial sum.
- Anything bound to Blizzard's unit frames or status bars.

## Approaches

1. **A new module with its own Edit Mode box (chosen).** Free-standing, survives any UI
   replacement, and reuses two things that already exist: ForeverQuests' quest and XP-buff logic
   (git history, confirmed in game 9 November) and the per-layout Edit Mode store of
   ForeverCombatText.
2. **Bring back the exp-bar overlay.** Rejected: it is bound to Blizzard's bar, which EllesmereUI
   hides.
3. **Add the line to an existing module.** Rejected: none is about quests, and a module is
   switched on and off as a whole.

## How it works

- **Which quests count**, reward-data loading and the XP-buff bonus are as in the ForeverQuests
  spec ("Which quests count", "XP buffs"): `C_QuestLog.IsComplete`, `GetQuestLogRewardXP`,
  `HaveQuestRewardData` with one `C_TaskQuest.RequestPreloadRewardData` per quest and a 5 second
  wait, Well-Rested (429959) at +1% per stack read out of combat, each reward rounded down.
- **The box** is a frame on `UIParent` holding one font string (`GameFontNormal`'s face at the
  layout's size), sized to the text and anchored at the saved point, so the text grows from where
  the player put it. It takes the mouse for the tooltip. Default: centre of the screen, 250 below;
  font size 14, slider 8 to 32.
- **SavedVariables:** `RazzhUIQuestXPDB = { version = 1, text = { [layout key] = { point, x, y,
  fontSize } } }`, the same keying as `ForeverCombatTextDB.text`.

## Secret values

`GetQuestLogRewardXP`, `UnitXP` and `UnitXPMax` were confirmed not secret in or out of combat
(9 November). They are still checked with `issecretvalue`; if any is secret the line hides and the
`XP` log says so. Own auras can't be read in combat, so the last XP-buff reading is kept.

## In-game checks

1. The line shows with a completed quest, and its XP matches the turn-in (`TURNIN` logs the paid
   XP next to the prediction).
2. The line updates without `/rl` when a quest completes, is turned in or abandoned (`LINE`).
3. Dragging and the font size survive `/rl` and are per layout (`SAVE`, `EDITMODE`).
4. The sample shows in Edit Mode with no completed quests and goes on leaving it.
5. The tooltip reads right, including the level-up case. By eye.
6. No errors with the line shown in combat (`devlog.sh --errors`).

## Left to the builder

File split, event coalescing, the tooltip's anchor.

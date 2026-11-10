# ForeverUnitFrames: detached player power bar

Date: 2026-11-10. Decision record: `docs/adr/0002-detach-the-player-power-bar-by-reparenting-blizzards-bar.md`.

## Intent

The user wants their power (rage, mana, energy) where their eyes are in a fight: just above the
action bars in the middle of the screen, not in the player frame in the corner. The player frame
keeps the portrait, name and health. The health bar grows into the space the power bar leaves, so
the frame doesn't show an empty slot.

## What it does

- **Health bar:** in the player frame, the health bar covers both the health row and the power
  row below it (Forever's layout: health 124×15 at (87, −46), power 124×10 at (87, −61), so the
  health area becomes 124×25). Its mask is stretched by the same 10 px. Health text stays
  centred on the bar.
- **Power bar:** Blizzard's own player mana bar (`PlayerFrame_GetManaBar()`), with its colour,
  text, full-power pulse and spend feedback, moves into a holder frame of ours on `UIParent`. It
  fills the holder, with a dark background behind it and a thin black outline, and a plain
  rectangular mask (`Unit_BarMask`) instead of the player frame's shaped one.
- **Edit Mode:** the holder is an Edit Mode box named "Player Power Bar" (LibEditMode). Players
  drag it, and its dialog has **Width** (60–600, default 270) and **Height** (4–40, default 12)
  sliders plus Reset Position. Default position: bottom centre, 150 px up (above the default
  action bars; the user will place it).
- Position and size are kept per Edit Mode layout, account-wide, in `ForeverUnitFramesDB`.

## Constraints

- The bars are protected frames: layout changes only out of combat. If Blizzard re-lays out the
  frame in combat (it calls the two layout functions on vehicle and alternate-power changes), our
  layout is applied when combat ends. A `/reload` in combat waits for combat to end as well.
- Never replace Blizzard functions or fields: `hooksecurefunc` on the two layout functions only.
- Power values are secret; our code never reads them.

## Non-goals (first slice)

- Target, party or pet frames; a separate class-resource or alternate power bar; hiding the
  power bar; a Settings-panel copy of the sliders; text format options.

## Left to the builder

- Exact outline and background look (tuned in game with the user); mask offsets if the stretched
  health mask shows the frame art's divider or bleeds past the frame (in-game check).

## In-game checks

| Check | How it shows |
|---|---|
| Health bar fills both rows without bleeding past the art | screenshot from the user; `LAYOUT` log line with sizes |
| Power bar sits in the holder, updates rage/mana, text shows | screenshot; `POWER` log line on apply |
| No blocked actions on login, `/reload`, entering/leaving combat, Edit Mode drag | `devlog.sh --errors` |
| A re-layout in combat is deferred and applied after | `DEFER` / `APPLY` log lines |
| Edit Mode box drags, sliders resize, Reset Position works, survives `/reload` | user, plus `SAVE` log lines |

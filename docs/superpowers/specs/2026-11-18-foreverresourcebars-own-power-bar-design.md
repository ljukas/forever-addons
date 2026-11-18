# ForeverResourceBars: a power bar of our own

Date: 2026-11-18. Decision record: `docs/adr/0005-draw-the-player-power-bar-ourselves.md`.
Replaces the mechanism of `2026-11-10-foreverunitframes-detached-power-bar-design.md`; the druid row
(`2026-11-12-foreverunitframes-off-form-power-design.md`, `2026-11-13-...-row-animation-design.md`)
stays as designed.

## Intent

The user is moving to EllesmereUI for unit frames. ForeverUnitFrames' power bar is Blizzard's
player-frame bar moved into our holder, and EllesmereUI switches that bar's events off, so it froze
on the power type it had at login (a druid in Bear Form saw mana instead of rage, 18 November 2026).

The user's words: "this should not be a basic bugfix, but instead moves this addon to be a RazzUI
ResourceBar addon. It should work independently of external unitframes, and the end result is that
it should work as before. But without being bound to the blizzard unit frame."

## Goals

- The power bar looks and behaves as it does today (place, size, border, background, art per power
  type, smooth fill, the druid row, Edit Mode dialog) with Blizzard's player frame, EllesmereUI's,
  any other, or none.
- The bar follows the player's power type at once: a druid entering Bear Form gets a rage bar.
- The power numbers show on the bar, following the game's Status Text settings.
- The addon is a resource bars module: named for what it does, with room for more bars later.

## Non-goals

- Blizzard's spend flash, full-power pulse and mana cost preview. They compare or subtract secret
  power values, which addon code can't do. Chosen by the user: "Bar plus numbers".
- Anything on Blizzard's player frame. The health bar growth and the removal of Blizzard's mana bar
  are deleted (the user: "Remove our frame changes"). A player still showing Blizzard's player
  frame sees its mana bar as well as ours.
- Hiding Blizzard's player frame. That is a unit frame addon's job.
- Other resources (combo points, health, a target's power), vehicles, and a tooltip on the bar.
- Changing the druid row's behaviour.

## Anti-goals

- No code that reads, hooks, re-parents or writes anything of `PlayerFrame` or its bars.
- No comparison, arithmetic or branch on a power value. Values go from the API to a widget.
- No special case for EllesmereUI or any other addon by name.

## Constraints

- Player power is secret in and out of combat (CLAUDE.md, 5 November 2026). `UnitPowerType` is not.
- Confirmed in game already: a status bar of ours takes `UnitPower`/`UnitPowerMax` as they are
  (`OffFormPower.lua`, since 12 November 2026), and `UNIT_POWER_FREQUENT`/`UNIT_MAXPOWER` reach an
  addon's frame for the player.
- From the API docs only, unconfirmed in game: `AbbreviateLargeNumbers` and `FontString:SetFormattedText`
  take secret arguments from addon code (`SecretArguments = "AllowedWhenTainted"`), and
  `UnitPowerPercent(unit, powerType, unmodified, curve)` returns the percentage through a curve.
- **Order:** `feat/suite-modules` (roadmap step 2) makes this addon a RazzhUI module: it edits the
  TOC, `Core.lua` and the changelog and adds `Options.lua`. This step is built on `main` after that
  branch has merged, and renames what it added.
- Nothing has been released (no tags), so the rename breaks no player's install. The user's own
  saved bar positions need the one-time command below.

## Approaches

1. **A status bar of ours fed from the player's power events** (chosen). The fill the player sees
   today is already our frame (`fill` in `PowerBar.lua`); only its values, art choice and numbers
   come from Blizzard's bar. The druid row proves the mechanism in game.
2. **Our own instance of Blizzard's mana bar template, driven by Blizzard's functions.** Would keep
   the pulse and spend flash, but runs Blizzard's secret arithmetic tainted. Errors per frame.
3. **Keep Blizzard's bar and switch its events back on** when another addon turns them off. Small,
   keeps every Blizzard feature, but stays bound to Blizzard's frame. Rejected by the user's
   direction.

The user handed the how over; approach 1 is Claude's pick, for the reasons in ADR 0005.

## Design

### The rename

| | From | To |
|---|---|---|
| Folder, TOC | `addons/ForeverUnitFrames/ForeverUnitFrames.toc` | `addons/ForeverResourceBars/ForeverResourceBars.toc` |
| Title (after step 2) | `\|cffd6b380RazzhUI\|r Unit Frames` | `\|cffd6b380RazzhUI\|r Resource Bars` |
| SavedVariables | `ForeverUnitFramesDB` | `ForeverResourceBarsDB` |
| Notes | moves the player frame's power bar... | the player's power bar as a bar of its own, placed and sized in Edit Mode, with a druid's other powers in a row above it |

Also: `.pkgmeta` (`package-as`), `.luacheckrc` (the addon's `globals` entry; `SLASH_FOREVERUNITFRAMES_ART1`
goes), the changelog's title, the options page's wording where it says "Unit Frames", and the comment
in `addons/ForeverCombatText/EditMode.lua` that names the old addon. `## X-Category` stays
`Unit Frames` (the genre). ADR 0002 gets a status line pointing at ADR 0005; older specs and plans
keep the old name, as history.

The changelog's `## Unreleased` section is rewritten to describe the addon as it now is (nothing
under it was released): the power bar, the druid row, the numbers, the Edit Mode layout fix. The
line about the health bar growing goes.

### The database

`ForeverResourceBarsDB = { version = 1, powerBar = { [key] = {...} } }`: the same layout and keys as
`ForeverUnitFramesDB` version 1 (`Database.lua`, `EditMode.lua`), so a carried-over file needs only
the table's name changed. `DB_VERSION` stays 1; no migration, since an addon can't read another
addon's SavedVariables.

Carrying the user's saved positions over, once, with the game closed (Git Bash):

```sh
cd "/c/Program Files (x86)/World of Warcraft/_forever_/WTF/Account" && for f in */SavedVariables/ForeverUnitFrames.lua; do sed 's/ForeverUnitFramesDB/ForeverResourceBarsDB/' "$f" > "${f%ForeverUnitFrames.lua}ForeverResourceBars.lua"; done
```

Without it every layout starts from the defaults (bottom centre, 270 x 12).

### The bar (`PowerBar.lua`)

Kept as they are: the holder (the Edit Mode box), the background, the border frame, `DEFAULTS`,
`CreateBackground`, `Interpolation`, `SetLayout`, and that `OffFormPower.lua` parents its row to the
border.

- **Fill:** the existing `fill` status bar, from 2 px left of the holder to 3 px right of it (where
  the art met the border in game, 10-11 November 2026; today that is `barOutset.left` plus
  `fillOutset.right`). One table, `ns.PowerBar.fillOutset = { left = 2, right = 3 }`, which
  `OffFormPower.lua` reads for its own fills.
- **Values:** `fill:SetMinMaxValues(0, UnitPowerMax("player", powerType))` and
  `fill:SetValue(UnitPower("player", powerType), interpolation)`, on `UNIT_POWER_FREQUENT` and
  `UNIT_MAXPOWER` for the player.
- **Power type:** `UnitPowerType("player")` at load, on `PLAYER_ENTERING_WORLD` and on
  `UNIT_DISPLAYPOWER` for the player. On a change the art is set and the fill jumps to the new
  power's value (`Immediate`, then `SetToTargetValue`), as the row's bars do.
- **Art**, by Blizzard's rules for the player frame (`UnitFrameManaBar_UpdateType`), from
  `PowerBarColor[powerToken]`:
  1. `atlasElementName` -> atlas `UI-HUD-UnitFrame-Player-PortraitOn-Bar-<name>`, untinted (mana,
     rage, focus, energy, runic power);
  2. else `atlas` -> that atlas, untinted;
  3. else `UI-HUD-UnitFrame-Player-PortraitOn-Bar-Mana-Status` tinted with the colour
     `UnitPowerType` returns, or the entry's `r, g, b`, or left as mana when there is neither.

  This is a function of its own that takes the token and colours and returns atlas and tint, so a
  reviewer can check it by reading.
- **Dead or ghost:** on `PLAYER_DEAD`, `PLAYER_ALIVE`, `PLAYER_UNGHOST` and with the power type, the
  fill's texture is desaturated at half alpha while `UnitIsDeadOrGhost("player")`.
- **Shown:** always, with its background and border. (Today they hide with Blizzard's bar.)
- **Layout changes apply at once**, in combat too: the frames are ours and unprotected.
  `Layout.lua` goes.

Deleted from `PowerBar.lua`: the slot frame, `ApplyBar` and everything on Blizzard's bar (re-parenting,
mask, pulse layout), `SyncArt`, `SyncValues`, every `hooksecurefunc` and `HookScript`, `Request`,
`maskOutset`, `barOutset`.

Deleted files: `HealthBar.lua`, `Layout.lua`, `Dev/ArtProbe.lua` (all of it is about the player
frame's art or tunes outsets that are now constants). The TOC's do-not-package block keeps only
`## OptionalDeps: ForeverDev`. The log tags `LAYOUT`, `DEFER`, `APPLY` and `ART` leave the shim's
list.

### The numbers

Blizzard's player bar shows text when the Status Text setting is on, or while the mouse is over the
bar, in the display mode the player picked. Ours does the same from the same CVars:

| `statusTextDisplay` | Shown |
|---|---|
| `NUMERIC`, `NONE` | centre: `1234 / 5000` |
| `PERCENT` | centre: `25%` |
| `BOTH` | right: `1234`; left: `25%`, for mana only (as Blizzard's bar) |

- Visible while CVar `statusText` is `"1"`, or while the mouse is over the bar.
- Three font strings (centre, left, right) in Blizzard's `TextStatusBarText` font, on a frame above
  the fill and below the border, placed as on Blizzard's bar: centre, and 2 px in from each end.
- Values: `AbbreviateLargeNumbers(UnitPower(...))` and `AbbreviateLargeNumbers(UnitPowerMax(...))`,
  put together by `SetFormattedText("%s / %s", ...)`; percent from
  `UnitPowerPercent("player", powerType, false, CurveConstants.ScaleTo100)` through
  `SetFormattedText("%.0f%%", ...)`. Blizzard rounds the percentage up, ours rounds to nearest:
  accepted, since rounding up needs arithmetic.
- Updated with the fill while visible, when the mouse enters or leaves, and on `CVAR_UPDATE`.
- The bar takes mouse motion only; clicks go through to the world.
- No zero text, no hiding at zero maximum, no prefix: those branch on the values.

If the in-game check shows that one of these calls refuses a secret value, the numbers are left out
of this step and the PR says so; the bar ships without them.

### Options and Edit Mode

`EditMode.lua` and `Snap.lua` are unchanged apart from names. `Options.lua` (from step 2) keeps its
one button that opens Edit Mode.

### In-game checks

The old `ForeverUnitFrames` must be off while testing (it would still pull Blizzard's bar into a
holder of its own); after the merge `scripts/link.sh` drops its stale link.

| Check | How | Devlog |
|---|---|---|
| The bar follows the power type | Bear Form and back, EllesmereUI's unit frames on, then off | `POWER type RAGE <atlas>` then `POWER type MANA <atlas>`; no errors |
| Same in combat, and after `/rl` in combat | shift while fighting; `/rl` mid-fight | same lines; `--errors` clean |
| Login in a form | log out in Bear Form, log in | `POWER type RAGE` by the time the world shows |
| Secret numbers reach the text | Status Text on, each display mode; then off and hover | `POWER text <mode> shown`; no "secret" error |
| Dead look | die, release, resurrect | `POWER dead true` / `false`; grey at half alpha |
| Smooth fill, size, place, per layout | Edit Mode dialog, switch layouts | `SAVE`, `EDITMODE` lines as today |
| The druid row | as its own spec | `OFFFORM` lines as today |
| Saved positions carried over | run the command, log in | the bar is where it was |

## Left to the builder

- Whether the numbers live in `PowerBar.lua` or a small file of their own.
- The exact events for re-reading the Status Text CVars (`CVAR_UPDATE` is what Blizzard's bar uses;
  check that it fires for both CVars when the setting changes in Options).
- Whether mouse motion should also pass through to the world (`SetPropagateMouseMotion`), if hover
  still shows the numbers with it on.
- The wording of the changelog lines and the options page.

## Claude's calls, for the user to check

- Numbers follow the game's Status Text settings instead of getting settings of their own.
- The rounding of the percentage (nearest, where Blizzard rounds up).
- The bar is always shown.
- `Dev/ArtProbe.lua` and `/fufart` are deleted rather than trimmed.
- The PR is marked breaking (`feat(foreverresourcebars)!: ...`) for the rename, though nothing was
  released.
- Saved positions are carried over by a command, not by code.

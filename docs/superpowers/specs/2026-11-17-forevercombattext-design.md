# ForeverCombatText: movable combat text for the player

Date: 2026-11-17. Decision record: `docs/adr/0003-move-combat-text-by-mirroring-blizzards-messages.md`.

## Intent

The red, green and white text for things that happen to the player ("15 (Block)", "-42", "+120",
"Dodge") always starts at the centre of the screen, on top of the character, and scrolls a fixed
distance. The user wants to place it in Edit Mode and set how far it scrolls, how long it lasts and
how big it is.

## Goals

- A new addon, `addons/ForeverCombatText` (scaffold with `scripts/new-addon.sh`).
- An Edit Mode box named "Combat Text" that players drag. The box is the scroll path: text starts
  at one end and travels the box's height.
- Sliders in the box's Edit Mode dialog: **Scroll Length**, **Duration**, **Font Size**.
- Position and settings kept per Edit Mode layout, account-wide.
- While Edit Mode is open, sample messages scroll in the box so the settings can be judged.

## Non-goals (first slice)

- The damage and healing numbers over *other* units (the engine draws those in the world).
- Choosing which events show, their wording or colours: Options > Combat keeps owning that.
- A font face choice, an outline option, a Settings-panel copy of the sliders.
- Snapping the box to other Edit Mode boxes (ForeverUnitFrames' `Snap.lua`).

## Anti-goals

- No Lua errors or blocked actions from Blizzard's combat text, ever: we write nothing on its
  frame or tables (ADR 0003).
- No text lost: if our hook can't be installed, Blizzard's text stays visible where it was.

## Approaches

Mirror Blizzard's messages (picked), rewrite Blizzard's numbers, or replace its event handling.
ADR 0003 has the trade-offs. The user handed over the how; mirroring is Claude's call.

## How it works

### Source of messages

- `Blizzard_CombatText` is load-on-demand (loaded when "Scrolling Combat Text for Self" is on).
  Wait for it with `EventUtil.ContinueOnAddOnLoaded("Blizzard_CombatText", ...)`.
- `hooksecurefunc(CombatText, "AddMessage", OnMessage)`. `OnMessage(_, message, scrollFunction,
  r, g, b, displayType, isStaggered)` runs after Blizzard's. `displayType` is `"crit"`,
  `"sticky"` or nil. If `CombatText` or its `AddMessage` is missing, log it and do nothing more.
- Once hooked, `CombatText:SetAlpha(0)`. The frame must stay shown: its `OnEvent` returns early
  when it isn't visible.
- `message` may be secret. Pass it to `SetText` only. Colours, `displayType` and `isStaggered`
  come from Blizzard's own tables and are plain values; guard with `issecretvalue` anyway and
  fall back to white, no crit, no stagger.
- Ignore `scrollFunction`. The direction is the CVar `floatingCombatTextFloatMode_v2`: `"1"` up,
  `"2"` down, anything else arc (as in `CombatTextMixin:UpdateDisplayedMessages`). Read it when a
  message arrives.

### Drawing

- A holder frame on `UIParent` (not protected, never touched by secure code): width 200, height =
  Scroll Length. Font strings are the holder's own, on Blizzard's layer (`BACKGROUND`) with its
  font object (`CombatTextFont`), kept in a free list for reuse. At most 20 lines, like Blizzard's
  pool; with a long Duration more can be alive than Blizzard ever has, so a message past the cap
  replaces the oldest line.
- When the holder is hidden (the UI hidden with Alt-Z, a cinematic) its lines are dropped and new
  messages ignored, as Blizzard's frame does.
- Each line is anchored by its centre to the holder's start edge (bottom when scrolling up or in
  an arc, top when scrolling down) and moved every frame by the holder's `OnUpdate`. `OnUpdate`
  is only set while lines are active.
- The animation is a port of `CombatText.lua` / `CombatTextUtil.lua`, with the settings in place
  of the constants:

  | Blizzard | Ours |
  |---|---|
  | start → end, 225 units | holder's start edge → the other edge (Scroll Length) |
  | `MessageScrollSpeed` 1.9 s | Duration |
  | `MessageFadeOutTime` 1.3 s | Duration × 1.3 / 1.9 |
  | `MessageHeight` 25 | Font Size |
  | crit height 30 → 60 → 30 over 0.05 s / 0.2 s, and a crit stays at the start | Font Size × 1.2 → × 2.4, same times |
| a `"sticky"` line stays at the start, except in an arc (nothing passes it today) | same |
  | arc radius 150, alternating sides | Scroll Length × 150 / 225 (Claude's call: Blizzard's proportions, so arc text rises two thirds of the box and swings past its sides) |
  | stagger ±10 px sideways when `isStaggered` | same |
  | a new line starts behind the last one (16 + 10 spacing), up to 130 back of 384, then steps 80 sideways | same, with 16 scaled to Font Size × 16 / 25 (Claude's call: matches Blizzard at the default). Up and arc lines start a line (25) beyond 384, so their limit is 105 behind the start edge; down, 130. The 130, 80 and 10 are not scaled by the world frame's size as Blizzard's are |

- The maths (position at time t for each mode, alpha, crit height, where a new line starts) lives
  in pure functions in `Scroll.lua`, taking plain numbers, apart from the frame code.

### Edit Mode

- LibEditMode, the way ForeverUnitFrames uses it: a `.pkgmeta` external pinned to tag `19`,
  loaded namespaced (`Libs\LibEditMode\namespaced.lua`, `embed.xml`) as `ns.LibEditMode`.
- `LEM:AddFrame(holder, OnMoved, default, L.COMBAT_TEXT)` and `LEM:AddFrameSettings` with three
  sliders:

  | Setting | Range | Step | Default |
  |---|---|---|---|
  | Scroll Length | 50–600 | 5 | 225 |
  | Duration (seconds) | 0.5–5 | 0.1 | 1.9 |
  | Font Size | 10–60 | 1 | 25 |

- Default position (Claude's call): where Blizzard's text starts, so an untouched install looks
  the same. Blizzard anchors each line's top to the screen's bottom edge at
  `384 * WorldFrame:GetHeight() / 768` in UIParent units (`CombatText.lua:457`, `:484`, `:506`),
  which is the screen's centre only at UI scale 1 and lower on screen otherwise. Scrolling down,
  a line's top starts there; scrolling up or in an arc, `AddMessage` starts it one line lower (at
  the new string's `GetBottom()`). The default puts the box's start edge on the centre of that
  first line for the direction in use (`ns.Display.DefaultY`): the box hangs below 384 for down
  and stands on it for up and arc. The line's height is taken as 25; if the pool's reset leaves
  the string at the font's native height the up and arc default is too high; only the eye can
  tell, since Blizzard's line can't be measured once it holds secret text.
- Reset Position uses the direction in use at login.
- The start edge stays put when Scroll Length changes. When the direction flips between up and
  down the box stays and the text starts from its other end. LibEditMode re-derives the
  anchor point after every drag (`normalizePosition`), so the saved point is often `CENTER` or
  `TOP`: the position is saved as LibEditMode gives it, and a Scroll Length change shifts the
  saved offset by what that anchor point would otherwise let the start edge move
  (`ns.Scroll.ShiftForLength`), saving the whole position with it.
- Sample messages while Edit Mode is open (LibEditMode's enter and exit callbacks): one a
  second, cycling a hit, a heal and a crit in Blizzard's colours ("-25", "+120", "-250"; plain
  amounts need no GlobalString). Real messages still show.
- Per-layout storage is a copy of ForeverUnitFrames' `EditMode.lua` scheme: layout name as the
  key, `"<name> @ <player GUID>"` for character-specific layouts, validated on read with the
  default as fallback, and the create, rename and delete callbacks. One difference: LibEditMode
  names the last layout in the list as the created one, but Blizzard inserts a new account layout
  before the character layouts, so "create" finds the new layout itself (the one not seen before)
  and never replaces an entry that exists. ForeverUnitFrames still has the original behaviour.

### Saved data

`ForeverCombatTextDB` (account-wide), with `Database.lua` documenting it and a `DB_VERSION = 1`
migration like ForeverUnitFrames':

```
version = 1
text    = { [layoutKey] = { point, x, y, length, duration, fontSize } }
```

## Constraints

- Lua 5.1, `ns` only, no globals but `ForeverCombatTextDB`.
- Released TOC metadata as CLAUDE.md says (`## Category: Forever Enhanced Addons`,
  `## X-Category: Combat`); a `CHANGELOG.md` line under `## Unreleased`.
- `ns.log` tags, listed in the Core.lua shim: `LOADED`, `HOOK`, `MSG`, `SAVE`, `EDITMODE`.

## In-game checks

| Check | How it shows |
|---|---|
| The hook fires and gets Blizzard's arguments | `HOOK hooked`; `MSG` lines: `issecretvalue(message)`, colour, `displayType`, float mode |
| The default box is where Blizzard's text starts | by eye against a screenshot of Blizzard's (its line's `GetTop()` is secret, so it can't be logged); `MSG` has the box's bottom and top and the world frame's and UIParent's heights |
| A secret message displays through our `SetText` | text visible in the box in a fight; `devlog.sh --errors` clean |
| Blizzard's copy is hidden and still running | no second copy of the text anywhere; ours keeps showing |
| Low-health warning and Blizzard's handler stay error-free | `devlog.sh --errors` after a fight that drops below 20% health |
| Drag, sliders, layout switch, `/rl` keep their values | `SAVE` lines; `EDITMODE apply` has the values in use after each change and after `/rl` |
| Up, down and arc all follow Options > Combat | by eye, one fight each |
| Crit pop and stacking look like Blizzard's | by eye |

The `MSG` line is logged once per session for each secrecy, display type, colour and direction
(`ns.dev:LogOnce`), not per hit.

## Left to the builder

- File split beyond `Scroll.lua` (pure maths) and the Edit Mode file.
- Exact sample messages and their GlobalStrings.
- How the box's anchor is kept on the start edge when the direction or length changes.

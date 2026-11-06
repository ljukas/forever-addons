# ForeverActionBars: red out-of-range tint on action buttons

Date: 2026-11-06 · Status: draft, awaiting approval · Addon: ForeverActionBars (new)

## Intent

When an ability is out of range of the current target, Blizzard only turns the small hotkey
number red. In a fight that's easy to miss. This addon makes **the whole button** show it: a
translucent red wash over the icon plus a thin red edge, so you can see at a glance which
buttons won't reach. The red hotkey stays as it is.

Prior art compared (see the mockups shown in the session): Blizzard's default (hotkey only),
the red icon tint of tullaRange, Bartender4 and ElvUI, a desaturate-then-red variant, and a red
wash with a red edge. The user picked **the wash with a red edge** ("option D").

How others combine range with the other button states: ElvUI (LibActionButton-1.0's
`UpdateUsable`) lets out-of-range *replace* the icon colour, so out-of-mana blue and unusable grey
disappear while out of range, and it colours either the button or the hotkey, never both.
EllesmereUI's source isn't public. Its changelogs show it tints icons red and has had to fix
the tint getting stuck (for example on a slot emptied by a talent swap) and being inconsistent.

## Goals

1. **Out-of-range wash.** While an action button's ability is out of range of its target, a
   red, semi-transparent wash covers the icon and a thin red edge outlines the button. It looks
   like the "D" mockup: wash at roughly 35–40 % opacity, edge about 2 px, both in Blizzard's red
   (`RED_FONT_COLOR`, the same red the hotkey uses).
2. **Signals stack.** The wash is drawn *over* Blizzard's own icon colouring, never instead of
   it. Out of range plus out of mana shows blue under red. Out of range plus unusable shows
   grey under red. In range, the button looks exactly like Blizzard's.
3. **Every standard Blizzard action bar:** the main bar and all the extra bars (MultiBar*).
   The pet bar comes later (goal 4).
4. **Pet bar: evidence now, wash later** (decided by the user). The pet bar gets **no wash at
   launch**. Its range updates are hooked only to collect evidence (in-game check 2), and the
   wash is turned on in a later PR once that evidence shows pet range is measured from the pet.
   The requirement for that PR: on the pet bar, "out of range" means the *pet* can't reach the
   target. A hunter standing back with the pet on the target must not see the pet's melee
   abilities washed red. Every other button that reaches `ActionButton_UpdateRangeIndicator`
   (pet buttons, the gamepad pet flyout) gets no wash in this version.
5. **The wash never sticks.** It goes away when the target is dropped or dies, when the ability
   has no range check (self buffs), when the slot is emptied or the action changes (talent swap,
   dragging a spell off, bar paging, stance or form change).

## Range source

- **Primary: Blizzard's own result.** Every bar ends in one global function,
  `ActionButton_UpdateRangeIndicator(button, checksRange, inRange)`
  (`Blizzard_ActionBar/Shared/ActionButton.lua`):
  - action bars call it on `ACTION_RANGE_CHECK_UPDATE` (event payload `slot, isInRange,
    checksRange`; range checks are enabled per slot with `C_ActionBar.EnableActionRangeCheck`);
  - the pet bar calls it from an `OnUpdate` timer (`TOOLTIP_UPDATE_TIME`) with the `checksRange`
    and `inRange` returns of `GetPetActionInfo(i)` (`PetActionBar.lua`).

  The addon post-hooks it (`hooksecurefunc`). The wash is shown when `checksRange and not
  inRange`, the same condition Blizzard uses to turn the hotkey red, so the wash and the hotkey
  always agree.
- **Clearing paths Blizzard doesn't route through that function.** When a slot is emptied,
  `ActionBarActionButtonMixin:Update` resets the hotkey colour directly and never calls
  `ActionButton_UpdateRangeIndicator` (`ActionButton.lua`, the "no texture" branch). The addon
  must also clear the wash there. Goal 5 lists the cases, and each one is checked in game.
- **Secret values.** Forever's generated docs flag neither the `ACTION_RANGE_CHECK_UPDATE`
  payload nor `C_Spell.IsSpellInRange`'s return as secret, and `GetPetActionInfo` isn't in the
  generated docs at all. Midnight has surprised us before (`UNIT_COMBAT` amounts are secret even
  out of combat), so the addon never branches on `checksRange` or `inRange` directly.
  **Decided behaviour (Claude's call after the builder check):** the wash's visibility is
  driven by the client's secret-safe setters, `Region:SetAlphaFromBoolean(value, alphaIfTrue,
  alphaIfFalse)` (`SimpleRegionAPIDocumentation.lua`, `SecretArguments = "AllowedWhenTainted"`).
  `checksRange` sets the overlay frame's alpha (true → 1, false → 0) and `inRange` sets the
  wash's alpha (true → 0, false → the wash opacity). The two multiply, so the result is
  "shown only when checksRange and not inRange", with no comparison, negation or branch in Lua.
  It works the same whether the values are secret or not, and it can't stick: every update
  overwrites both alphas. `issecretvalue` is still used, but only for the `RANGE` logging.
  If the game rejects a secret value even there, phase 2 below takes over.
- **Fallback, phase 2, only if the game shows it's needed** (decided by the user): if the range
  values come back secret in combat, estimate the target's distance from the player's learned
  spells, the way LibRangeCheck-3.0 does. Ask `C_Spell.IsSpellInRange(spellID, "target")` for
  learned spells with known ranges, turn the answers into a distance band, and wash a button
  when the band is beyond that action's range. This is **not built in the first version**. The
  first version's logging decides whether it's needed.
  - **Known gap:** `C_Spell.IsSpellInRange` measures from the player, and the API has no
    pet-to-target distance, so the fallback can't serve the pet bar. If pet range is secret,
    pet buttons fall back to Blizzard's behaviour (hotkey only, or nothing).

## Non-goals

- No reskin of the bars: icon, border, fonts, layout and Edit Mode stay Blizzard's.
- No settings panel and no SavedVariables in this version. Colour, opacity and edge are fixed.
  Options can come later.
- No change to the hotkey colouring (Blizzard already does it) and none to the usable, mana or
  unusable icon colours.
- No range display for stance, possess or extra-action buttons that don't run through
  Blizzard's range path.
- No support for third-party bar addons (Bartender, Dominos and the like). Only Blizzard's buttons.
- **No gamepad action bars** (decided by the user: not a focus yet). Forever's
  `Blizzard_GamepadActionBars` buttons handle range in their own
  `GamepadActionBarButtonMixin:RefreshRange` and never call the hooked function, so they get no
  wash. Covering them later means a second hook.
- **No pet-bar wash in this version** (goal 4).
- The learned-spells fallback (phase 2, above).

## Anti-goals (would be a failure even if it "works")

- Any Lua error, taint or `ADDON_ACTION_BLOCKED` from the action bars, in or out of combat.
  Action buttons are secure frames: the addon only adds its own textures to them and shows or
  hides those textures. It never calls protected methods, never changes the buttons' attributes,
  size, position or scripts, and never writes fields Blizzard reads.
- Overwriting Blizzard functions or mixin methods. Post-hooks only.
- A wash that's still there after the cause is gone (goal 5).
- A wash that hides *which* spell is on the button. The icon must stay recognisable.
- Covering Blizzard's own overlays in a way that hides them: cooldown swipe, proc glow
  ("spell activation alert"), autocast shine on the pet bar, the hotkey and charge count must
  still be visible.

## Constraints

- Forever client, interface 16001, Midnight 12.x addon API. Verify every API in
  `.cache/wow-ui-source` before use (CLAUDE.md).
- **Native, no custom art.** The wash and edge are built from the client's own primitives
  (colour textures, or a Blizzard atlas for the edge if one fits). The red is `RED_FONT_COLOR`.
- **Layering.** The wash sits above the icon and below the cooldown swipe, hotkey, count and
  proc glow (goal 1 and the anti-goals). The builder picks the draw layer and sublevel from the
  button template's own layers.
- New addon from `template/Addon` via `scripts/new-addon.sh ForeverActionBars`:
  `## Category: Forever Enhanced Addons`, `## X-Category: Action Bars`, the ForeverDev shim, MIT,
  and a `CHANGELOG.md` line under `## Unreleased`.
- Mixin methods are copied onto each button when it's created. Hooking
  `ActionBarActionButtonMixin` after login won't reach existing buttons, so any per-button hook
  goes on the button instances. The global `ActionButton_UpdateRangeIndicator` can be hooked once.

## In-game checks (instrumentation the first version ships with)

All logged with tag `RANGE` through `ns.log` / `ns.dev:LogOnce` / `LogChanged`, dev-only work
inside `if ns.dev.enabled then`.

1. **Are range values readable?** For action bars and the pet bar separately, out of combat and
   in combat: is `checksRange` or `inRange` ever secret? (Log once per bar kind and situation.)
   Secret in combat → phase 2 is needed.
2. **Pet range is from the pet: deferred, collected as evidence.** The user has no pet class
   to test with yet, so this isn't a launch check. Instead the addon keeps **evidence across
   sessions** in a `Knowledge.lua` (`ns.dev:Observed`, read with
   `scripts/observed.sh ForeverActionBars`). For each pet button range result it records the
   spell, `checksRange`/`inRange` (or "secret") and the player's distance band to the target,
   if it can be had cheaply (for example from `C_Spell.IsSpellInRange` on a learned
   long-range spell). The evidence that settles it is a pet melee ability reporting *in range*
   while the player is clearly out of melee range. Whenever a pet class gets played, the data
   accumulates by itself and we check it then. A project memory records what to look for.
3. **Clearing:** target dropped, target dies, slot emptied by dragging, talent or spec swap, bar
   paging, stance/form change. In each case no wash remains.
4. **Stacking looks right:** out of range plus out of mana, and out of range plus unusable, on a
   real button.
5. **Layering:** cooldown swipe, proc glow, pet autocast and hotkey stay visible over the wash.
6. **No taint:** `scripts/devlog.sh --errors` shows nothing after a fight with the addon on.

## Decided by the user

- Rendering: option D, a red wash plus a red edge over the icon. The red hotkey stays.
- Signals stack: the wash goes over the out-of-mana and unusable colours, never replaces them.
- A new addon, **ForeverActionBars**.
- All standard bars. The pet bar is skipped at launch: evidence only, with the wash in a later
  PR, measured from the pet.
- No pet class to test yet: pet range is checked later from evidence the addon collects
  across sessions, not at launch.
- Gamepad action bars are out of scope for now.
- If range turns out secret: estimate it from learned spells, like other addons. Built only if
  the first version's logging shows it's needed.

## Claude's calls (the user can override)

- **No options and no SavedVariables in the first version.** Fixed look, fixed red.
- **Red is `RED_FONT_COLOR`**, matching the hotkey, rather than a custom red.
- **Secret range values:** drive the wash with `SetAlphaFromBoolean` so secret values still
  show correctly. Rejected alternatives: freezing the wash (it could stick for a whole fight,
  breaking goal 5) and clearing it (the wash would vanish exactly when it's needed).
- **Phase 2 is a separate PR**, decided from the in-game logs.
- **Pet-bar fallback:** if the pet's range is secret or measured from the player, the pet bar
  keeps Blizzard's behaviour rather than getting a wrong wash.

## Left to the builder

- How the overlay is created on each button (on first range update, or once per button at
  load) and which draw layer and sublevel it uses, within the layering constraint.
- Whether the edge is four thin colour textures, a Blizzard atlas or the button's own border
  region recoloured, as long as it adds no custom art and doesn't overwrite Blizzard fields.
- How the "slot emptied or action changed" clearing is caught (a post-hook on each button's
  `Update`, `ACTIONBAR_SLOT_CHANGED`, `ACTIONBAR_PAGE_CHANGED`, `UPDATE_BONUS_ACTIONBAR`, the pet
  bar's update), as long as every case in goal 5 is covered.
- File layout and any extra `ns.log` lines beyond the `RANGE` checks above.

## Untested

Nothing here has run in game yet. Whether the range values are readable in combat, whether pet
range is measured from the pet, and whether the wash clears in every case all depend on the
in-game checks above.

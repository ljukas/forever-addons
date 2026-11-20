# RazzhUIPowershift: keep action bar 1 on the form's page through a powershift

## Why

A druid powershift macro (`/cancelform`, then `/cast Bear Form`) leaves action bar 1 on the caster
page for three seconds, although the character is in Bear Form the whole time. Pressing a key in
that window casts a caster spell, which fails with "You are in shapeshift form".

## What the client does (probed 20 November 2026, ForeverDev `FORM` tag, build 70959)

- At the press, the Bear Form cast succeeds (`UNIT_SPELLCAST_SUCCEEDED` 5487) and the power type
  stays rage, but `GetShapeshiftForm()`, the stance bar's active flag, the bonus bar offset and
  the `[form:N]` and `[bonusbar:N]` conditions all read "no form".
- Exactly 3.0 seconds later, in and out of combat, `GetShapeshiftForm()` and `[form:N]` read the
  form again. No event fires. The bonus bar offset stays 0 until the next real form change.
- `/cancelaura Bear Form` in place of `/cancelform` behaves the same. A plain `/cast Bear Form` in
  Bear Form only leaves the form.
- The cast's spell ID and the power type are readable in combat; the form's aura only out of it.

EllesmereUI's action bars (9.9.1) page bar 1 with a secure state driver on `EABBar_MainBar`. Its
`[form:N]` clauses bring the page back once the form reads right, so the bar is wrong for those
three seconds only.

## Goals and non-goals

- Bar 1 (icons and keys) stays on the form's page through a powershift, in combat.
- Works for any form with a page of its own (Bear, Dire Bear, Cat), without naming spells.
- Not a goal: Blizzard's own action bar. Its page is written by insecure code that can't be held
  back; the module does nothing when EllesmereUI's bar isn't there.
- Not a goal: the "You are in shapeshift form" error itself. Leaving a form to cast is the
  client's doing, and for three seconds it doesn't know about the form.
- Anti-goal: a bar that shows the form's page when the character is in caster form and can't be
  put right.

## Approaches

1. **Another macro** (`/cancelaura`). Tested, same gap. Rejected.
2. **Hold the page from a secure click (chosen).** Only secure code can repage a bar in combat,
   and only the player's key press can tell a powershift from leaving the form on purpose.
3. **Leave it to EllesmereUI.** They can do the same inside their own bar. Worth reporting, but
   not in our hands.

Within 2, the module could give the player a whole powershift button (its own macro text per form)
or one line to add to their own macro. The line is chosen: no spell names, no macro text of ours,
and the player's macro keeps its tooltip and stays theirs.

## Design

The player adds one line at the top of their powershift macro:

```
#showtooltip
/click RazzhUIPowershiftHold
/cancelform
/cast Bear Form
```

- `RazzhUIPowershiftHold` is a `SecureHandlerClickTemplate` button, never shown, with a frame
  reference to `EABBar_MainBar`. Its click snippet: if `GetShapeshiftForm() > 0` and no hold is
  set, store the bar's current `state-page` on the bar as the attribute `razzhuipowershift-hold`.
  A press from caster form, or a second press inside the three seconds, changes nothing.
- The module wraps the bar's `OnAttributeChanged` (`SecureHandlerWrapScript`). The pre-body, for
  `state-page` with a hold set:
  - the new page equals the held one: the client reports the form again. Clear the hold, let the
    change through.
  - `GetShapeshiftForm() == 0` and no override, vehicle, possess or temporary shapeshift bar:
    return `false`, which stops EllesmereUI's `_onstate-page` handler, so the buttons, the keys
    and the mirror on `MainActionBar` stay on the held page. It also writes the held page to
    `MainActionBar`'s `actionpage` again, since Blizzard's controller has just set it to 1.
  - anything else (another form, a vehicle): clear the hold, let the change through.
- **Releasing a hold that will never be confirmed** (the recast failed: global cooldown, no mana,
  stunned). Secure code has no clock, so:
  - out of combat, insecure code releases any hold older than 4 seconds, and every hold on
    `PLAYER_REGEN_ENABLED`: clear the attribute and set `state-page` to its own value again, which
    runs EllesmereUI's handler with the page its driver last chose;
  - in combat it can't. The bar shows the form's page in caster form until the player presses the
    powershift key again (which takes the form) or any real form change happens. This is the
    module's known limit.
- Setup runs out of combat once `EABBar_MainBar` exists (after `PLAYER_ENTERING_WORLD`; on
  `PLAYER_REGEN_ENABLED` when a reload happened in combat). Without that frame the module logs it
  and does nothing.
- No SavedVariables, no slash command. The options page (`RazzhUI.RegisterOptions`) holds only the
  macro line to copy and whether EllesmereUI's bar was found.

## Layout

`addons/RazzhUIPowershift/`: the TOC (a RazzhUI module, `## OptionalDeps: EllesmereUIActionBars`
so the bar exists first), `Core.lua` (dev shim), `Hold.lua` (the button, the wrap, the release),
`Options.lua`, `CHANGELOG.md`. The `FORM` probe stays in `addons/ForeverDev/Probes.lua` and ships
in its own PR first.

## In-game checks

All with `scripts/devlog.sh --tag FORM` (fields `eab`, `blizz`) and a `HOLD` tag from the module:

1. Powershift in Bear Form, out of combat and in combat: `eab` and `blizz` stay 9 through the gap,
   `HOLD` logs set and cleared 3 seconds apart, and a bear ability key fires the bear ability.
2. Two presses within 3 seconds: still 9, one hold.
3. Leaving Bear Form without the macro: the bar goes to page 1 at once.
4. A failed recast out of combat (press during the global cooldown): the bar returns to page 1
   within about 4 seconds.
5. EllesmereUI's own page sync (`MainBarPageSync`) doesn't move the bar during a hold.
6. `scripts/devlog.sh --errors`: no blocked actions or taint from the wrap.

## Left to the builder

Whether `/click` needs the mouse button and down arguments under the key-down CVar (register the
button for both); the exact wording on the options page.

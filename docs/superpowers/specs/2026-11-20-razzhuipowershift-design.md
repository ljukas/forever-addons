# RazzhUIPowershift: a one-key powershift the client keeps up with

## Why

A druid powershift macro (`/cancelform`, then `/cast Bear Form`) leaves the client thinking the
character has no form for three seconds. Action bar 1 drops to the caster page, the form's
abilities fail with "Must be in Bear Form", and caster spells fail with "You are in shapeshift
form". Nothing can be cast until the three seconds are over.

## What the client does (probed 20 November 2026, ForeverDev `FORM` tag, build 70959)

- At the macro's press, the Bear Form cast succeeds (`UNIT_SPELLCAST_SUCCEEDED` 5487) and the
  power type stays rage, but `GetShapeshiftForm()`, the stance bar's active flag, the bonus bar
  offset and the `[form:N]` and `[bonusbar:N]` conditions all read "no form".
- Exactly 3.0 seconds later, in and out of combat, `GetShapeshiftForm()` and `[form:N]` read the
  form again. No event fires. The bonus bar offset stays 0 until the next real form change.
- `/cancelaura Bear Form` in place of `/cancelform` behaves the same. A plain `/cast Bear Form` in
  Bear Form only leaves the form.
- The client refuses the form's abilities during the gap: Enrage went through only once the form
  read right again.
- **Leaving the form and taking it again as two steps, about a second apart, has no gap**: the
  power type turns to mana, then the form, the bonus bar and the bar's page are right at once.
- The cast's spell ID and the power type are readable in combat; the form's aura only out of it.

## Goals and non-goals

- One key press powershifts, in combat, and the form's bar and abilities work straight after.
- Bear Form (or Dire Bear Form) and Cat Form, each with its own key.
- Works with any action bars: nothing depends on EllesmereUI.
- Not a goal: making powershift macros work. A macro runs once per press, so it can't take two
  steps.

## Approaches

1. **Another macro** (`/cancelaura`). Tested, same gap. Rejected.
2. **Hold the bar's page through the gap** (a secure click from the macro, and a wrap on
   EllesmereUI's bar). Built and tested: the bar stayed on the form's page, but the client still
   refused the form's abilities, so it only looked right. Removed.
3. **Two steps from one key (chosen).** A key bound straight to a button clicks it on the way down
   and on the way up. Down leaves the form, up takes it again, and the client never has to guess.
4. **Leave it to Blizzard.** The gap is the client's. Worth reporting; not in our hands.

## Design

- Two secure action buttons, never shown: `RazzhUIPowershiftBear` and `RazzhUIPowershiftCat`,
  registered for `AnyDown` and `AnyUp`.
- `Bindings.xml` lists `CLICK RazzhUIPowershiftBear:LeftButton` and
  `CLICK RazzhUIPowershiftCat:LeftButton` under the header "RazzhUI Powershift" in the game's
  Keybindings (category AddOns), named "Powershift: Bear Form" and "Powershift: Cat Form".
- Each button's `OnClick` is wrapped (`SecureHandlerWrapScript`). The pre-body sets, on the way
  down, `type = "cancelaura"` and `useOnKeyDown = true`; on the way up, `type = "spell"` and
  `useOnKeyDown = false`. A secure action button acts on one of the two clicks only, the one
  `useOnKeyDown` names, so both now act.
- The `spell` attribute is the form's spell name, which both actions read. It is taken from the
  stance bar (5487 or 9634 for bear, 768 for cat), out of combat, on entering the world and on
  `UPDATE_SHAPESHIFT_FORMS`; a change in combat waits for `PLAYER_REGEN_ENABLED`.
- From caster form the key just takes the form: the cancel finds nothing to cancel.
- Holding the key keeps the character in caster form until it is let go.
- **Action bar slots** (`Keys.lua`, druids only). A slot whose macro contains
  `/click RazzhUIPowershiftBear` (or `...Cat`) gives its key to the module. Out of combat, the
  module scans the action slots (`C_ActionBar.GetActionText` is a macro's name, `GetMacroBody` its
  text) and sets priority override bindings (`SetOverrideBindingClick`), which win over the bars'
  own. It runs again, debounced, on `ACTIONBAR_SLOT_CHANGED`, `UPDATE_MACROS`, `UPDATE_BINDINGS`,
  `UPDATE_SHAPESHIFT_FORMS` and when combat ends, and does nothing when what it wants hasn't
  changed. Identifying the macro by what it clicks needs no naming convention.
  - The bars beside and above bar 1 (`MULTIACTIONBARxBUTTONn`) always show the same slots: the
    key goes straight to the form's button.
  - Action bar 1 (`ACTIONBUTTONn`) shows another page per form on the same keys: the key goes to
    a dispatcher, `RazzhUIPowershiftKey1` to `12`. As the key goes down, its wrapped `OnClick`
    works out the slot showing (page and bonus bar, in `ActionBarController_UpdateAll`'s order).
    If that slot has a claim (the attribute `claim-<slot>`, the form's spell name, set by the
    scan for the caster page and the three form pages), it powershifts with that form; otherwise
    it presses the slot (`type = "action"`), on the click the player's key-down setting picks. So
    a bear macro on the bear page and a cat macro on the cat page share a key, and the caster
    page's slot on that key keeps working.
  - The slot shows the macro's icon and tooltip. A mouse click runs the macro, whose `/click` is
    the button's "up" step, a plain cast of the form's spell: it takes the form, or leaves it
    when the character is in it.
- No SavedVariables, no slash command. The options page (`RazzhUI.RegisterOptions`) says where to
  bind the keys and how they behave.

## Layout

`addons/RazzhUIPowershift/`: the TOC (a RazzhUI module), `Core.lua` (dev shim), `Shift.lua` (the
buttons, the wrap, the spell names), `Keys.lua` (the bar slots' keys and the dispatchers),
`Bindings.xml`, `Options.lua` (the page and the binding
names), `CHANGELOG.md`. The `FORM` probe stays in `addons/ForeverDev/Probes.lua` and ships in its
own PR first.

## In-game checks

With `scripts/devlog.sh --tag FORM` and the module's `SHIFT` tag:

1. `SHIFT spells` names Bear Form (or Dire Bear Form) and Cat Form, or `none` for a form the
   character doesn't have.
2. A quick tap of the bear key in Bear Form, out of combat and in combat: `SHIFT` logs down then
   up, `FORM` shows form 0 then form 1 with offset 3 and no 3-second gap, and Enrage fires
   straight after. If a tap is too quick for the server to see two steps, the gap comes back:
   that is the design's one unproven assumption.
3. The same from caster form, and from Cat Form.
4. Holding the key for a second, then letting go: caster form while held, the form on release.
5. With "cast on key down" both on and off in the game's options.
6. A macro with `/click RazzhUIPowershiftBear` on a slot of a bar beside bar 1: `KEYS` logs
   `<key>=RazzhUIPowershiftBear` and the key powershifts as in check 2, with EllesmereUI's bars
   on. Moving the macro moves the key; removing it logs `none` and gives the key back.
7. On action bar 1, a bear macro on the bear page and a cat macro on the cat page in the same
   position, and an ordinary spell there on the caster page: `KEYS` logs
   `<key>=RazzhUIPowershiftKey<n>[<slot>:Cat Form <slot>:Bear Form]`; the key powershifts bear in
   Bear Form and cat in Cat Form, and casts the ordinary spell in caster form. Another key of
   bar 1 with no macro on any page is untouched.
8. `scripts/devlog.sh --errors`: no blocked actions.

## Known limits

- A tap of the key powershifts; a mouse click on the bar slot only casts the form's spell.
- Bar 1's dispatcher works out the showing slot the way Blizzard's bar does. With EllesmereUI
  paging bar 1 by a modifier or a target, a slot without a macro is pressed on the page Blizzard
  would show, not the one EllesmereUI shows.
- Of two macros with the same name, the first is the one read.
- A macro moved or made in combat takes effect when the fight ends.
- If the recast fails (global cooldown, no mana), the character is in caster form, as with any
  powershift. Nothing is left in a wrong state.

## Left to the builder

The wording on the options page.

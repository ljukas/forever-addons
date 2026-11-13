# ForeverUnitFrames: the off-form power row slides in and out

## Intent

A druid's off-form power row (`OffFormPower.lua`) pops in and out above the detached power bar on a
form change. It should slide up from the power bar and fade in when it appears, and slide back down
and fade out when it leaves.

## Scope

- **In:** the row appearing and leaving because of a form change or a form learned.
- **Not animated:** login and `/reload`, the Edit Mode settings (on/off, height), and the power
  bar's backdrop showing or hiding. A row that stays while its bars change (one bar to two, energy
  swapped for mana) changes at once, as before.
- **No setting.** One fixed duration, 0.2 s both ways (`SLIDE_DURATION`).

These are Claude's calls; the user asked for slide-up and fade on enter and exit and said to go
ahead with the rest.

## Approaches

1. **One `AnimationGroup` on the row, played backwards to enter (chosen).** The group is the leave
   motion: a `Translation` down by the row's height and an `Alpha` from 1 to 0. `Play(true)` enters.
   Blizzard's help-plate buttons do the same (`Blizzard_HelpPlate.lua`). The row at rest has no
   offset or alpha to restore, and the client does the easing.
2. **A hand-rolled `OnUpdate`** moving the row's anchor and alpha each frame. Turning around
   mid-slide is trivial, but it is code we maintain for what the client already does.
3. **Animate each piece where it is today** (bars on the row, borders on the power bar's border
   frame, the power bar's background stretched upward). Three animations to keep in step, and a
   stretched texture can't fade in part.

## Design

- Everything of the row belongs to the row, so one animation carries it: the borders move from the
  power bar's border frame to a child frame of the row at the border's level, and the row gets a
  background of its own (`ns.PowerBar.CreateBackground`) instead of the power bar's background
  growing upward. `ns.PowerBar.SetHeadroom` goes away.
- The row sits in a clipping frame whose bottom edge is the power bar's top, so the row comes out
  from behind the power bar instead of crossing its text.
- `SetRowShown(shown, animate)` is the one place the row shows or hides. Without `animate`, or with
  the backdrop hidden, it snaps. A slide the other way that is still playing turns around from where
  it is: the new play starts `(1 - progress) * duration` in.
- Only the event handler (`UNIT_DISPLAYPOWER`, `UPDATE_SHAPESHIFT_FORMS`, `SPELLS_CHANGED`) asks for
  animation; `SetLayout` never does.
- All of it is our own unprotected frames, so it runs in combat. No power value is read.

## In-game checks

| Check | How |
|---|---|
| The row slides up and fades in on entering a form, and back out on leaving | Shift caster → bear → caster before Cat Form; `OFFFORM slide in/out` in the devlog |
| The row comes out from behind the power bar (the clip applies to an animated child) | Watch the slide; no bars over the power bar's text |
| No flash of the full row at the end of the slide out | Watch the last frame of leaving |
| The row at rest looks as before, now that its background is its own texture | Compare with the confirmed one-bar look; no seam between row and power bar |
| A slide turned around mid-way continues from where it was | Shift out and back within 0.2 s; `OFFFORM slide … from <offset>` is above 0 |
| No slide at login or `/reload` in a form | `/rl` in bear form; if it slides, the forms weren't known at the first layout |

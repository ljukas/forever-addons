# RazzhUIResourceBars: mana regen spark

## Goal

After a spell spends mana, a spark travels along the mana bar from its left edge to its right edge
in five seconds and arrives as mana starts to regenerate again (the five-second rule), so the
player can see how long is left before regen resumes (user, 25 Nov 2026).

## Scope

- **When it starts:** on the player's `UNIT_SPELLCAST_SUCCEEDED` for a spell whose mana cost
  (`C_Spell.GetSpellPowerCost`) is above zero. A new such cast restarts the spark from the left.
  Instants, spells with a cast time (the cost comes off at the end of the cast) and shapeshifts
  alike.
- **Where:** on whichever bar shows mana at that moment: the power bar while the player's power is
  mana, else the mana bar of a druid's Other Powers row while that row is in. With neither (a
  druid in a form with Other Powers off) the timer runs unseen, and the spark shows where it has
  got to if a mana bar comes back within the five seconds. The spark moves between the two bars on
  a form change without restarting.
- **Look:** the cast bar's spark (`ui-castingbar-pip`), as tall for its bar as the cast bar's: 1.8
  times the bar it is on (8×20 on the 11-high player cast bar, CastingBarFrame.xml). About a seventh as
  wide as it is tall, thinner than the cast bar's 0.4, which looked too heavy in game (user,
  25 Nov 2026), and never under 3 wide, so it doesn't thin to a sliver on a low bar (user,
  26 Nov 2026). Above the border, as the cast bar has it. On the Other Powers row, which is
  cut off just past its border, the spark reaches at most 2 past the bar's top and bottom instead,
  so it is cut nowhere and stays centred. It travels the bar as its border
  shows it, edge to edge, at a constant speed. At five seconds it disappears.
- **Setting:** a Regen Spark checkbox (default on) in the power bar's Edit Mode dialog, for every
  class but warriors and rogues. Stored per layout as `regenSpark` next to the other fields in
  `RazzhUIResourceBarsDB.powerBar`; missing or invalid reads as the default, so no migration.

Non-goals: the two-second regen ticks after the five seconds, energy ticks, a spark in Edit Mode as
a preview.

## Secret values

Mana is secret, so a drop in mana can't be seen and nothing is read from the bar. The spark's
place is the clock's alone: `(GetTime() - start) / 5` of the bar's width. The cast's `spellID` is
readable for the player's own casts unless the spell is flagged secret
(`SecretWhenUnitSpellCastRestricted`); a secret `spellID` or cost starts no spark, as
CostPrediction.lua has it.

## Known gaps

- Mana spent by anything that is not a spell cast with a mana cost starts no spark.
- The cost is read when the cast succeeds. A cast made free by an effect the cast itself used up
  (Clearcasting) may read as its normal cost by then and start a spark the game doesn't count.
  The devlog's `REGEN start` lines show it if it happens.
- A channel: whether `UNIT_SPELLCAST_SUCCEEDED` comes at its start is unchecked in game.
- That Forever pauses regen for five seconds at all is taken from Vanilla, not from the client's
  source. `GetManaRegen()` is logged at the start and the end of the spark to show it.

## Approaches

1. **A frame of ours moved by the clock** (chosen): one spark, re-anchored each frame from
   `GetTime()`, parented to the bar that shows mana. It can change bars mid-flight and restart at
   any moment.
2. **An unseen status bar running 0 to 5, with the spark hung on its fill's edge**, as Blizzard's
   bars place theirs: the client does the placing, but there is still an update per frame to feed
   it, and a second one would be needed for the Other Powers row.
3. **An animation group's Translation over five seconds:** no per-frame code, but its distance is
   fixed when it starts, so a bar that changes width or a spark that changes bars mid-flight would
   need the animation rebuilt from an offset.

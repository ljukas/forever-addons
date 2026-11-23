# Spell scaling in spell tooltips (RazzhUI Tooltip)

## Intent

Forever's spell tooltips show a spell's base damage or healing, with talent bonuses already in
it, but never what your attack power (AP) or spell power (SP) adds, nor how much of it the spell
gets. Rake reads "29 damage and 66 over 9 sec." whatever your AP. The player wants to hover **their
own spells** (spellbook, action bars) and see what the spell really does with their current
stats, and its coefficient.

Success: hovering Swipe on a druid shows the AP share and the resulting damage; hovering Wrath
shows the SP coefficient and the resulting damage, and both numbers match what hits for.

## Findings that shape the design (23 November 2026)

- Forever's own spell data (wago.tools, product `wowf`, build `1.60.1.71037`, `SpellEffect`
  table, CSV downloadable by script) has `EffectBonusCoefficient` (SP) and
  `BonusCoefficientFromAP` (AP) per effect. SP coefficients are real (Wrath rank: 0.571).
  **AP coefficients are 0 for Swipe (780) and Rake (1822):** the server applies AP scaling that
  the client data doesn't carry.
- Tooltip numbers are the description's `$s1` and friends: base points times talent modifiers
  (Swipe 25 → 27, Rake 27 → 29 and 60 → 66, all +10%). They don't move with AP or SP, so tooltips
  can't be used to deduce coefficients.
- `UnitAttackPower`, `UnitRangedAttackPower`, `GetSpellBonusDamage(school)` and
  `GetSpellBonusHealing` are `SecretWhenUnitStatsRestricted`: readable unless
  `C_Secrets.ShouldUnitStatsBeSecret()` says otherwise (when that happens in game is unknown).
- In game, hit amounts are secret (`UNIT_COMBAT`) and `COMBAT_LOG_EVENT_UNFILTERED` is
  restricted. Outside the game, **Advanced Combat Logging** writes `Logs/WoWCombatLog-*.txt`,
  where each damage line carries the amount, absorbed/blocked/resisted and, in the advanced
  fields, a unit's AP and SP.
- SpellPowerCoefficients (CurseForge `spc-forever`) does the SP part from the same client data.
  Its licence is unclear and its source isn't public, so nothing is taken from it.

## Goals

- A tooltip line on the player's own damage and healing spells: the coefficient, what the
  player's current AP/SP adds, and the resulting total (talented tooltip value + bonus).
- SP coefficients for every class's spells, generated from the client data, not typed by hand.
- AP coefficients measured from the player's own combat logs by a repo script, so nobody reads
  numbers off the screen.

## Non-goals

- Crit, hit, armor, target resistances, buffs' % modifiers or expected DPS. The line shows what
  stats add to one cast, nothing more.
- Other players' or NPCs' spells, item "Use:" spells, pet spells.
- Weapon-damage abilities (Claw, Maul, Shred, Sinister Strike: "weapon damage + N"). Their real
  damage depends on the weapon swing, not a coefficient. Deferred.

## Anti-goals

- A wrong number shown as fact. An AP coefficient enters the table only from a fit the script
  calls confident, and every value records where it came from.
- Errors or taint when stats are secret.

## Approaches

1. **Client data for SP, measured AP table (chosen).** A script builds the SP table from the
   client's `SpellEffect`; a second script fits AP coefficients from combat logs and writes them to
   a second data file. Covers every class for SP at once, and AP spell by spell as logs come in.
2. **SP only.** Simple and fully trustworthy, but does nothing for Swipe and Rake, the case that
   started this.
3. **Deduce from tooltip changes on gear swaps** (the player's first idea). Doesn't work: tooltip
   numbers don't move with AP or SP.

## Design

### Where it lives

The RazzhUI Tooltip module (`addons/ForeverTooltip`), as a new `Logic/SpellScaling.lua` plus two
data files. It already owns tooltip changes; a separate module would add a second tooltip hook
and options page for the same tooltip.

### Data

- `Data/SpellCoefficients.lua` (**generated**, never edited): `ns.SpellCoefficients[spellID] =
  { effects }`, one entry per damage/heal effect (`SCHOOL_DAMAGE`, `HEAL`, aura
  `PERIODIC_DAMAGE`/`PERIODIC_HEAL`, `HEALTH_LEECH`, absorb shields): effect index, kind
  (direct/periodic, damage/heal), base points, SP coefficient, client AP coefficient, tick period.
  Only class spells (`SpellClassOptions` gives the class family) with a non-zero coefficient or a
  damage/heal effect. `scripts/spell-data.sh` downloads `SpellEffect` and `SpellClassOptions`
  for a build and writes the file, stamped with the build. Re-run after a patch.
- `Data/APCoefficients.lua` (**generated** by the log script, reviewed in the PR): `[spellID] =
  { [effectIndex] = coefficient, source = "log 2026-11-24, 214 hits, R² 0.998" }`. Overrides the
  client's AP coefficient where present.

### Measuring AP coefficients (`scripts/ap-coefficients.sh`)

Reads `$WOW_DIR/Logs/WoWCombatLog*.txt` (Advanced Combat Logging on, `/combatlog` started).
For each of the player's `SPELL_DAMAGE` / `SPELL_PERIODIC_DAMAGE` lines on a non-crit: full
amount = amount + absorbed + blocked + resisted, and the player's AP from the advanced fields.
Group by spell, effect kind and target (same target type → same armor), then fit
`amount = a + b·AP`. Every multiplier (talents, armor) scales both terms, so the coefficient is
`base · b / a`, with `base` the client's base points. Bleeds and other armor-ignoring effects
need no armor reasoning at all.

The fit needs AP to vary within a group (buffs, gear swaps, forms, levels). A group with too
little spread, too few hits or a poor fit is reported, not written. The script prints what it
found per spell so the PR shows the evidence.

### The tooltip line

Hooked with `TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, ...)` and
shown only when the spell is one the player knows (`IsPlayerSpell` / `IsSpellKnown`).
One line per scaled effect, in Blizzard's green "Use:" style colour:

```
Swipe
...
Swipe 3 nearby enemies, inflicting 27 damage.
+3% AP: +4 = 31 damage
```
```
Wrath
...
+57.1% SP: +34 = 86-92 damage
```

**Talents scale the bonus too** (our call): a +10% talent multiplies the whole hit, so the line
uses `M = tooltip number ÷ base points` (27 ÷ 25) and shows `bonus = M · coefficient · stat` and
`total = tooltip number + bonus`. The tooltip number is read from the description (see "Left to
the builder"). When it can't be read, the line shows the unscaled bonus and no total.

**Low-level spells** (our call): Vanilla-era servers cut the SP coefficient of spells learned below
level 20 by 3.75% per level under 20; the client data doesn't carry that. The generator applies
it from the spell's level (`SpellLevels`), and the log script fits SP coefficients as well as AP
ones, so the rule is checked against real hits; a measured value overrides the computed one.

**Ranks** (our call): one AP coefficient covers every rank of a spell (same name, same class
family). A fit from any rank fills the others, and the source note says which rank it came from.

When `C_Secrets.ShouldUnitStatsBeSecret()` is true (or a stat comes back secret), the line shows
only the coefficient (`+3% AP`), no arithmetic.

#Review amendments (23 November 2026): the line is plain ASCII (the tooltip font has no arrow; it drew
a box in game), periodic effects read `+20% SP per tick, 4 ticks: +36 = 164 healing`, the client's
own AP coefficients are never shown (measured values only), absorbs other than Holy use spell
damage, and the line is added to GameTooltip only, for the tooltip's own spell.

## Options

One checkbox in the module's options page, "Show spell scaling in spell tooltips", on by
default.

## Slicing (agreed)

1. **PR 1:** the SP generator, `Data/SpellCoefficients.lua`, the tooltip line and its option,
   with an empty `Data/APCoefficients.lua`. AP spells show nothing yet.
2. **PR 2:** `scripts/ap-coefficients.sh`, built against a real Advanced Combat Logging log the
   player records, and the AP (and SP-check) values it measures.

## Left to the builder

- **Reading the tooltip number.** From `C_Spell.GetSpellDescription` or the tooltip's own
  lines: match each effect's number to its base points (the closest number ≥ base). Must fail
  quietly (no total) rather than guess, and survive locales the module doesn't translate yet.
- Exact effect types and aura types to include, from the `SpellEffect` enums.
- Which advanced-log field holds the caster's AP on Forever (to be confirmed from a real log).
- Fit thresholds (minimum hits, AP spread, R²).

## In-game checks

- Stats readable out of combat, and when they turn secret (`SPELLSCALE` tag: stats and
  `ShouldUnitStatsBeSecret` on each tooltip).
- The line appears only on the player's spells, in spellbook and on action bars, in both forms.
- The bonus matches real hits for Wrath (SP) and, once measured, Swipe and Rake (AP).

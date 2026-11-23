# Spell scaling in spell tooltips, PR 1 (spell power) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hovering one of your own damage or healing spells shows its spell-power coefficient, what your spell power adds, and the resulting total.

**Architecture:** A bash/awk script turns Forever's client spell data (wago.tools CSVs) into a generated Lua table. Pure functions in `Logic/SpellScaling.lua` do the maths and the tooltip-number matching. `SpellLine.lua` hooks spell tooltips through `TooltipDataProcessor` and adds the line. One option toggles it.

**Tech Stack:** Lua 5.1 (WoW Forever 1.60.x, Midnight API), bash + awk + curl, StyLua, LuaLS. LuaJIT (installed locally) runs the pure-logic checks from the scratchpad; the repo has no test suite and gets none in this PR.

**Spec:** `docs/superpowers/specs/2026-11-23-forevertooltip-spell-scaling-design.md`

## Global Constraints

- PR 1 only: SP coefficients from client data, the tooltip line and its option, an empty AP table. No log script.
- Data source: `https://wago.tools/db2/<Table>/csv?build=<build>`, product `wowf`; first build used `1.60.1.71037`.
- Only the player's own spells: `C_SpellBook.IsSpellKnown(spellID)` (bank defaults to Player).
- SP applies to non-physical schools only (`SchoolMask ~= 1`). Swipe's client coefficient of 1 is meaningless and must never show.
- Low-level rule: spells with `SpellLevel < 20` get `coef × (1 − (20 − SpellLevel) × 0.0375)`, floored at 0.
- Periodic effects: the client coefficient is per tick; ticks = `duration / EffectAuraPeriod`.
- Talents: `M = tooltip number ÷ expected base`; `bonus = M × coef × stat × ticks`; `total = tooltip number + bonus`. No tooltip number found → unscaled bonus, no total.
- When `C_Secrets.ShouldUnitStatsBeSecret()` is true or a stat reads secret: coefficient only, no arithmetic on the stat.
- Option `spellScaling`, default on, label "Show spell scaling in spell tooltips".
- Line colour: `GREEN_FONT_COLOR`. Line text, direct: `+57.1% SP: +34 → 88 damage`; periodic: `+20% SP ×4 ticks: +36 → 80 healing`; range: `→ 86–92 damage`; secret: `+57.1% SP` (periodic: `+20% SP ×4 ticks`).
- enUS strings in `ns.L`.

## Review Focus

1. **Spells with several effects** (Moonfire: direct + DoT; Rake: direct + bleed + energize). One line per scaled effect, matched to the right tooltip number; never two effects claiming the same number.
2. **Ranged descriptions** ("52 to 58 damage"): the match uses the low number, and the total shows a range.
3. **Spells missing from the table, or with no scaled effect** (Rake in PR 1, utility spells): no line, no error.
4. **Description not loaded yet** (`GetSpellDescription` returns `""` before `SPELL_TEXT_UPDATE`): unscaled bonus, no total, no error; the post-call runs again on rebuild.
5. **Secret stats** (in combat or instances, unknown which): coefficient-only line, and no comparison or arithmetic on any value that `issecretvalue` flags.

---

### Task 1: Generate the coefficient table

**Files:**
- Create: `scripts/spell-data.sh`
- Create: `addons/ForeverTooltip/Data/SpellCoefficients.lua` (generated)
- Create: `addons/ForeverTooltip/Data/APCoefficients.lua` (empty table, hand-written header)
- Modify: `addons/ForeverTooltip/ForeverTooltip.toc` (both data files, before `Logic/`)

**Interfaces:**
- Produces: `ns.SpellCoefficients[spellID] = { school = <mask>, level = <SpellLevel>, maxLevel = <MaxLevel>, baseLevel = <BaseLevel>, duration = <ms or 0>, effects = { { index = <EffectIndex>, kind = "damage"|"heal"|"absorb", periodic = <bool>, base = <EffectBasePointsF>, perLevel = <EffectRealPointsPerLevel>, variance = <Variance>, sp = <EffectBonusCoefficient>, ap = <BonusCoefficientFromAP>, period = <EffectAuraPeriod> }, ... } }`, and `ns.SpellCoefficientsBuild = "1.60.1.71037"`.
- Produces: `ns.APCoefficients = {}` (layout comment: `[spellID] = { [effectIndex] = coefficient, source = "..." }`, filled in PR 2).

- [ ] **Step 1: Write `scripts/spell-data.sh <build>`**: `set -euo pipefail`, sources `scripts/lib.sh`; downloads `SpellEffect`, `SpellClassOptions`, `SpellLevels`, `SpellMisc`, `SpellDuration` CSVs into a temp dir (curl, fail on non-200); one awk pass joins them by SpellID.
  - Keep: spells in `SpellClassOptions` with `SpellClassSet > 0` (class spells), `DifficultyID == 0` rows only.
  - Effect kinds: `Effect` 2 SCHOOL_DAMAGE / 9 HEALTH_LEECH → damage; 10 HEAL → heal; `Effect` 6/35 APPLY_AURA with `EffectAura` 3 PERIODIC_DAMAGE / 53 PERIODIC_LEECH → periodic damage, 8 PERIODIC_HEAL → periodic heal, 69 SCHOOL_ABSORB → absorb.
  - Keep a spell only if one of its kept effects has `sp > 0` or `ap > 0` (after dropping `sp` when `SchoolMask == 1`).
  - `duration` from `SpellMisc.DurationIndex → SpellDuration.Duration`.
  - Writes the Lua file with a header saying it's generated, by which command and from which build, then runs `stylua` on it.
- [ ] **Step 2: Run it** — `scripts/spell-data.sh 1.60.1.71037`. Expected: the file exists; `grep -c '^\t\[' addons/ForeverTooltip/Data/SpellCoefficients.lua` prints several hundred; it contains `[6780]` with `sp = 0.571`, `[8921]` with two effects, no `[780]` and no `[1822]`.
- [ ] **Step 3: Write `Data/APCoefficients.lua`**, list both files in the TOC, run `scripts/lint.sh`. Expected: clean.
- [ ] **Step 4: Commit** — `feat(forevertooltip): generate spell coefficients from client data` (script + data + TOC).

### Task 2: Pure scaling logic

**Files:**
- Create: `addons/ForeverTooltip/Logic/SpellScaling.lua` (TOC: after the data files)
- Test: `<scratchpad>/spellscaling_test.lua` (run with `luajit`, not committed)

**Interfaces:**
- Consumes: Task 1's effect and spell tables.
- Produces, on `ns.SpellScaling`:
  - `Coefficient(spell, effect) -> number` — SP coefficient after the low-level rule; 0 for physical.
  - `Ticks(spell, effect) -> integer` — 1 for direct effects; `floor(duration / period)` for periodic, min 1.
  - `ExpectedBase(spell, effect, playerLevel) -> number` — `(base + perLevel × (min(playerLevel, maxLevel > 0 and maxLevel or playerLevel) − baseLevel)) × ticks`, the untalented tooltip number.
  - `FindTooltipNumbers(description, expected[]) -> numbers[]` — for each expected value, the description number (low end of an "X to Y") whose ratio to it is closest to 1 within `[0.8, 1.6]`, each description number used once, nil where none fits.
  - `Bonus(coefficient, stat, ticks, multiplier) -> number` — `multiplier × coefficient × stat × ticks`, rounded down.
  - `FormatLine(kind, coefficient, ticks, bonus, total, totalHigh) -> string` — the line text per Global Constraints; `bonus` nil → coefficient only; `total` nil → no arrow.

- [ ] **Step 1: Write the failing checks** (load with `loadfile("addons/ForeverTooltip/Logic/SpellScaling.lua")("ForeverTooltip", ns)` after stubbing `ns.L`):
  - `Coefficient({ school = 8, level = 38 }, { sp = 0.571 }) == 0.571`
  - `Coefficient({ school = 8, level = 1 }, { sp = 0.429 })` ≈ `0.429 × 0.2875`
  - `Coefficient({ school = 1, level = 40 }, { sp = 1 }) == 0`
  - `Ticks({ duration = 12000 }, { periodic = true, period = 3000 }) == 4`; direct → 1
  - Rake-style: `FindTooltipNumbers("Rake the target for 29 damage and an additional 66 damage over 9 sec.", { 27, 60 })` → `{ 29, 66 }`
  - Moonfire-style with the DoT listed first in `expected`: numbers still land on the right effects.
  - `FindTooltipNumbers("", { 15 })` → `{ nil }`; `"Causes 52 to 58 Nature damage"` with `{ 54 }` → `{ 52 }` and its high end reported (return `{ { low = 52, high = 58 } }` entries; adjust the interface to that shape if cleaner — record the final shape in the Interfaces block).
  - `FormatLine("damage", 0.571, 1, 34, 88)` == `"+57.1% SP: +34 → 88 damage"`; `FormatLine("heal", 0.2, 4, nil)` == `"+20% SP ×4 ticks"`.
- [ ] **Step 2: Run** `luajit <scratchpad>/spellscaling_test.lua`. Expected: FAIL (file missing).
- [ ] **Step 3: Implement** the functions above. No WoW API calls in this file except `ns.L`.
- [ ] **Step 4: Run** the checks — all pass; `scripts/lint.sh` clean.
- [ ] **Step 5: Commit** — `feat(forevertooltip): compute spell power scaling`.

### Task 3: Tooltip line and option

**Files:**
- Create: `addons/ForeverTooltip/SpellLine.lua` (TOC: after `HealthBar.lua`)
- Modify: `addons/ForeverTooltip/Options.lua` (`spellScaling = true` default, checkbox), `addons/ForeverTooltip/Core.lua` (`ns.L` strings; `SPELLSCALE  SpellLine.lua` in the tag comment), `addons/ForeverTooltip/Database.lua` (layout comment gains `spellScaling = boolean`; no migration: defaults are read through `ns.Options.Get`)

**Interfaces:**
- Consumes: `ns.SpellCoefficients`, `ns.SpellScaling.*`, `ns.Options.Get("spellScaling")`.

- [ ] **Step 1: Hook** `TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, func)`. In `func(tooltip, data)`: bail unless the option is on, `data` is a readable table (`canaccesstable`, as Colors.lua does), `data.id` isn't secret, the spell is in `ns.SpellCoefficients` and `C_SpellBook.IsSpellKnown(data.id)`.
- [ ] **Step 2: Read stats.** `secret = C_Secrets.ShouldUnitStatsBeSecret()`; else SP = `GetSpellBonusDamage(schoolIndex)` for damage (school index = lowest set bit of the mask + 1), `GetSpellBonusHealing()` for heal/absorb; any `issecretvalue` → treat as secret.
- [ ] **Step 3: Build lines.** Expected bases → `FindTooltipNumbers(C_Spell.GetSpellDescription(id) or "", ...)` → multiplier, bonus, total → `tooltip:AddLine(FormatLine(...), GREEN_FONT_COLOR:GetRGB())` per scaled effect, then `tooltip:Show()` once if any line was added.
- [ ] **Step 4: Log** `ns.dev:LogChanged("stats", secret, "SPELLSCALE", "stats secret", secret)` and, under `if ns.dev.enabled then`, `ns.dev:LogOnce("spell" .. id, "SPELLSCALE", id, "expected", ..., "found", ..., "sp", ...)`.
- [ ] **Step 5: Option.** `L.SPELL_SCALING = "Show spell scaling in spell tooltips"`, `L.SPELL_SCALING_TOOLTIP = "Adds a line to your own damage and healing spells with how much of your spell power they get and what it adds."`; register as the other checkboxes.
- [ ] **Step 6:** `scripts/lint.sh` clean. **Commit** — `feat(forevertooltip): show spell power scaling in spell tooltips`.
- [ ] **Step 7: SavedVariables gate** — dispatch `savedvariables-guard` on the settings change; fix findings before Task 4.

### Task 4: Changelog

- [ ] Add under `## Unreleased` in `addons/ForeverTooltip/CHANGELOG.md`: "Your own damage and healing spells now show how much of your spell power they get and how much it adds, e.g. Wrath: "+57.1% SP: +34 → 88 damage". Turn it off in Options → AddOns → RazzhUI → Tooltip." Commit `docs(forevertooltip): note spell scaling in the changelog`.

## Step reviewers (Phase 5)

Core four, plus `savedvariables-guard` (settings key), a **UI reviewer** (tooltip hook, colour), a **shell reviewer** (`scripts/spell-data.sh`).

## In-game checks (Phase 6)

| Check | How it shows |
|---|---|
| Line on Wrath / Moonfire / Healing Touch / Rejuvenation in spellbook and on the action bar; none on Swipe, Rake, other players' spells | by eye |
| Talented numbers matched (no "→" missing on spells with a description) | `SPELLSCALE` `found` values |
| Stats readable out of combat; whether they turn secret in combat / instances | `SPELLSCALE stats secret` |
| Bonus matches real hits: Wrath on a dummy, floating combat text ≈ total | by eye (PR 2's log script checks it properly) |
| No Lua errors or blocked actions | `scripts/devlog.sh --errors` |

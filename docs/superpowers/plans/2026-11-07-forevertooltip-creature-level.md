# ForeverTooltip: level difficulty colour on creatures, skull for ?? levels

One step, one PR. Builds on #30, which colours the level line of **player** tooltips by
`GetCreatureDifficultyColor`.

## Scope

- The level line of every unit tooltip (creatures, NPCs, critters, players) takes the difficulty
  colour: gray, green, yellow, orange, red (Blizzard's `GetCreatureDifficultyColor` scale, the one
  player tooltips already use).
- A `??` (skull) level shows Blizzard's skull icon in place of `??`
  (`|TInterface\TargetingFrame\UI-TargetingFrame-Skull:0|t`, used by Forever's
  `Camelot/PaperDollFrameStats.lua`), and the line is red.
- Name (class colour) and faction-line colouring stay players-only.
- Deferred: elite/rare markers, colouring the creature name by reaction.

## Seams

- `Colors.lua` post-call on `Enum.TooltipDataType.Unit`: split `GetPlayerUnit` into `GetUnit`
  (any readable unit) and a player check; `ColorLevelLine` runs for every unit.
- `Logic/LevelLine.lua`: new pure `ns.LevelLine.WithSkull(text, template, skull)` that replaces the
  leading `LevelText(template, -1)` with the skull version, or returns nil when the line doesn't
  start with it.
- Secret values: unreadable guid, unit, level or line text → the line is left as Blizzard drew it.

## Tasks

1. Level colouring for all units + skull swap (`Colors.lua`, `Logic/LevelLine.lua`, shim tag list,
   CHANGELOG line). Lint.

## Review focus

- `SetText` on a Blizzard tooltip line from a post-call: no taint into Blizzard's build, no secret
  text compared.
- `WithSkull` string handling: colour code prefix, `%` in templates, not touching a later `??`.
- Non-player units whose tooltip has no level line (objects routed as units, some NPCs): no error.

Reviewers: core four + UI reviewer.

## In-game checks

- Hover mobs below/at/above your level: level line gray/green/yellow/orange/red.
  `LEVEL` tag: `level line by type at N` (type path found for creatures).
- Hover a `??` mob (e.g. a high-level elite or boss): skull icon in place of `??`, red.
  `LEVEL` tag: `skull at line N`.
- `scripts/devlog.sh --errors` clean.

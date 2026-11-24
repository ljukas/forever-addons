# ForeverTooltip

## Unreleased

- Melee abilities that deal weapon damage (Claw, Shred, Maul, Heroic Strike, Cleave, ...) now show the damage they do with your current weapon damage, e.g. Claw: "154% of 51-65 weapon damage + 41 = 119-141 damage". Abilities that use a normalized weapon speed (Sinister Strike, Backstab) and ranged shots are left out for now.
- Your own damage, healing and shield spells now show how much of your spell power they get and how much it adds, e.g. Wrath: "+57.1% SP: +34 = 86-92 damage". For damage and healing over time the percentage is per tick and the amount is for the whole spell ("+20% SP per tick, 4 ticks: +36 = 164 healing"). Spell damage for one school only (Nature, Arcane, ...) counts for spells of that school. If the game hides your stats, the line shows just the percentage. Turn it off with "Show spell scaling in spell tooltips" in Options → AddOns → RazzhUI → Tooltip.
- When you hover a player, their name shows in their class colour.
- Their level line is coloured by how their level compares to yours, like quest difficulty: gray (far below you), green, yellow (around your level), orange, red (well above you, or ?? level).
- Creatures and NPCs you can attack get the same level colours, and a ?? level shows a skull instead of the question marks (red, unless the unit is friendly).
- Their Alliance/Horde line shows whether they're friend or foe: red for enemies, yellow for players you can attack who aren't hostile, green for allies.
- The health bar under unit tooltips now uses the same bar texture as your player frame, and sits in a panel with the tooltip's own border and background, joined to the tooltip.
- ForeverTooltip now needs RazzhUI installed, and is switched on or off with its checkbox on the RazzhUI page (Options → AddOns → RazzhUI).
- New option in Options → AddOns → RazzhUI → Tooltip: "Tooltip follows the cursor" shows tooltips for players, creatures and objects in the world next to your mouse instead of at the usual tooltip spot. Off by default. When it's on, "Tooltip grows towards" picks which side of the cursor the tooltip appears on: down and right, down and left, up and right (the default) or up and left.

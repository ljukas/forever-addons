local _, ns = ...

-- Attack power coefficients the client's spell data doesn't carry (the server applies them), measured
-- from combat logs. They override the client's `ap` in Data/SpellCoefficients.lua. Layout:
--
--   [spellID] = { [effectIndex] = coefficient, source = "where the number came from" }
--
-- Empty until the combat-log script measures them (docs/superpowers/specs/
-- 2026-11-23-forevertooltip-spell-scaling-design.md, PR 2).
ns.APCoefficients = {}

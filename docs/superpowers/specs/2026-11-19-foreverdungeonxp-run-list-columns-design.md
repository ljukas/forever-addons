# ForeverDungeonXP: run list columns and an XP per hour order

Date: 2026-11-19. One step, one PR.
Working PR title: `feat(foreverdungeonxp): rank the run list by experience per hour`.

## Intent

The user wants to find their best runs overall: the run list on the journal's left, ordered by
experience per hour across every dungeon. They also want each heading above the list to name what
stands under it, which it doesn't today:

- "Dungeon" and "Level" choose how the list is grouped. Neither is a column.
- Under "Level" stands the run's share of a level (44%), which the right side calls "Of a level".
- The experience per hour is only worked out for the selected run, on the right.

## Goals, non-goals

- **Goal:** one click on a heading ranks every listed run by experience per hour, best first, in
  one list without group headers.
- **Goal:** three headings, `Dungeon | Level | XP/h`, each over the thing it names in the rows.
- **Not in this step:** sorting by share of a level, by date or by total experience; a separate
  "group by" control; remembering the order between sessions (it lasts for the session, as today).
- **Must not happen:** a change to what is saved. `ForeverDungeonXPDB` is only read.

## Approaches

- **A. Three real columns (picked by the user).** The headings stay the list's only control. The
  two that name a category (Dungeon, Level) group the list as they do today; the one that names a
  number (XP/h) ranks it flat. One click to the ranking, no new control.
- **B. Grouping as its own control.** A "Group by: Dungeon / Level / None" dropdown beside the
  character picker, and headings that sort inside the chosen grouping. It could also answer "best
  run per dungeon", but adds a control and makes the ranking two steps.
- **C. XP/h in place of the Level heading.** Dropped: it loses the grouping by level.

## Design

What the user agreed to on 2026-11-19, from a text sketch. The rest is marked *(my call)*.

**Headings.** `Dungeon` on the left, then `Level` and `XP/h` on the right, in Blizzard's list
heading buttons as today, with the sort arrow on the active one.

| Heading | List | First click | Second click |
| --- | --- | --- | --- |
| Dungeon | grouped by dungeon, as today | dungeons A to Z | Z to A |
| Level | grouped by level, as today | highest level first | lowest first |
| XP/h | flat, no group headers | best rate first | worst first |

Inside a group the runs stay newest first. The list opens grouped by dungeon, as today.

**Rows.**

```
| Dungeon ^                   | Level |   XP/h |
 Deadmines - 1 run
   Bengan - Run 1 - 12 Nov        19    12,675
   9,418 XP (44%) - 194 kills - 44 min
```

- The first line keeps its title rules: the character's name when all characters are listed, the
  run's number under a dungeon header and the dungeon's name otherwise (so also in the flat list:
  "Bengan - Shadowfang Keep - 16 Nov"), then the date, which is cut off first.
- `Level` is the level the run started at (`run.level`), the number the level headers group by.
- `XP/h` is the rate the right side shows as "XP per hour": kill experience over the time from
  first to last kill, rested bonus included.
- The share of a level moves into the grey line, in brackets after the experience *(my call)*.

**Runs without a rate.** A run shorter than a minute has no rate (`ns.Format.PerHour` returns
nil, so one pack doesn't read as millions per hour). It shows "-" and stands last in the flat
list in both directions *(my call)*. Runs with the same rate go newest first.

**Width.** Two number columns don't fit beside the title in the list's 250 pixels. The list
grows to 300 and the window from 720 to 770, so the run's side keeps its width *(my call; the
numbers are to be judged in game)*.

## Left to the builder

- The column widths and label offsets, so each label stands over its column's numbers.
- The heading's text: "XP/h" unless it doesn't fit its column.
- Where the ordering lives: `Logic/RunList.lua` is pure and takes the new sort key; the rate
  comes from `ns.Format`.

## In-game checks

Nothing here depends on a value the client could hide: every number comes from saved runs. What
only the game can show is the look:

- each heading's label stands over its column, in all three orders;
- titles and the grey line fit at the new width, with all characters listed;
- the flat list's order matches the "XP per hour" shown for each run on the right.

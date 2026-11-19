# ForeverDungeonXP: run list columns and an XP per hour order

Date: 2026-11-19. One step, one PR.
Working PR title: `feat(foreverdungeonxp): rank the run list by experience per hour`.

## Intent

The user wants to find their best runs overall: the run list on the journal's left, ordered by
experience per hour across every dungeon. They also want each heading above the list to name what
stands under it, which it didn't:

- "Dungeon" and "Level" chose how the list was grouped. Neither was a column.
- Under "Level" stood the run's share of a level (44%), which the right side calls "Of a level".
- The experience per hour was only worked out for the selected run, on the right.

## Goals, non-goals

- **Goal:** one click on a heading orders every listed run by that column; XP/h gives the best
  runs across all dungeons.
- **Goal:** each heading stands over the thing it names in the rows.
- **Goal:** a row looks the same whatever the list is ordered by.
- **Goal:** rested and unrested runs compare: the rate leaves the rested bonus out.
- **Not in this step:** sorting by share of a level or total experience; a "group by" control;
  remembering the order between sessions (it lasts for the session).
- **Must not happen:** a change to what is saved. `ForeverDungeonXPDB` is only read.

## Approaches

First round, how sorting by a number meets the grouping:

- **A. Three columns, grouped or flat by heading (picked first, then replaced).** Dungeon and
  Level kept grouping the list under gold headers; XP/h ranked it flat. Built and tested in game
  on 2026-11-19. The user found it janky: the row's title changed with the order ("Run 1 - 12 Nov"
  under a dungeon header, "Wailing Caverns - 16 Nov" otherwise) and the headers came and went.
- **B. Grouping as its own control.** A "Group by" dropdown beside the character picker. One
  more control, and the ranking two steps away.
- **C. XP/h in place of the Level heading.** Loses the level.

Second round, after the test, one flat table in all three, differing in where the date goes:

- **Date in the grey line**, three headings. No way to order by date.
- **Date as its own column (picked by the user)**, four headings. Every heading is a real
  column, and the journal can open newest first.
- **One line per run**, no grey line. Denser, but loses the totals at a glance and has no place
  for the character's name.

## Design

Agreed with the user on 2026-11-19 from a mockup. The rest is marked *(my call)*.

**One flat table.** No group headers. A heading click only moves rows.

| Heading | First click | Second click |
| --- | --- | --- |
| Dungeon | A to Z | Z to A |
| Date | newest first | oldest first |
| Level | highest first | lowest first |
| XP/h | best first | worst first |

The list opens by date, newest first. Runs alike in the ordered column go newest first in both
directions *(my call: a turned order then doesn't also flip the runs inside a dungeon)*.

**Rows**, the same in every order:

```
| Dungeon                | Date   | Level |   XP/h |
  Shadowfang Keep          16 Nov     22     9,677
  13,994 XP (51%) - 120 kills - 31 min
```

- `Dungeon` is the run's dungeon name. The run's number ("Run 1") is no longer in the row; the
  right side's header still has it.
- `Date` is the day the run started. The time of day is no longer shown.
- `Level` is the level the run started at (`run.level`).
- `XP/h` is the rate without the rested bonus (below).
- The grey line has the run's experience, its share of a level in brackets, kills and time. With
  all characters listed it starts with the character's name in its class colour.

**Unrested rate.** The user asked for it: with the bonus in, rested runs stand out too much.
`ns.Format.Rate` is kill experience minus the rested bonus, over the time from first to last
kill. It is the number in the list, the number the list is ordered by, and the big "XP per hour"
on the right. A rested run shows its rate with the bonus as the small line under that
("27,085 with rested"). A run recorded before the rested bonus was kept has no figure to leave
out, so its whole rate counts as unrested; nothing saved can correct that.

**Runs without a value.** A run shorter than a minute has no rate (`ns.Format.PerHour` returns
nil, so one pack doesn't read as millions per hour). It shows "-" and stands last in the XP/h
order in both directions *(my call)*. The same goes for a damaged run without a name or level in
those columns' orders.

**Width.** The list is 380 wide and the window 850 (from 250 and 720), so the run's side keeps
its width *(my call; seen in game by the user on 2026-11-19 without objection)*. The columns
take 56 (date), 54 (level) and 62 (XP/h), which leaves the dungeon's name 158. The character
dropdown above the list is as wide as the list.

## In-game checks

No value here can be secret: every number comes from saved runs. What only the game can show is
the look:

- each heading's label stands over its column, and rows look the same in all four orders;
- the XP/h order matches the "XP per hour" shown for each run on the right;
- a rested run shows a lower rate in the list than its "with rested" line on the right;
- with all characters listed, the name starts the grey line in its class colour.

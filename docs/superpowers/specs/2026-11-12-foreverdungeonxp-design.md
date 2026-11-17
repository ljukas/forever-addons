# ForeverDungeonXP: kill XP per dungeon run

Date: 2026-11-12 · Status: approved 2026-11-12 · Addon: ForeverDungeonXP (new)

*(Amended while building: first named ForeverDungeonJournal. An unrelated third-party addon is
published under that exact folder name, so this one is ForeverDungeonXP, with `/fdxp`.)*

Lines marked *(my call)* were decided by Claude, not the user. Unmarked lines are the user's.

## Intent

After a dungeon run you want to know what it was worth: how much experience you got from killing
creatures, how big a share of a level that is, how many creatures you killed and how long it took.
With that kept per run and per dungeon, you can compare runs and dungeons and pick the best XP
for your level.

## Goals

1. **Record kill XP per run.** Every experience gain from killing a creature inside a 5-player
   dungeon is added to the current run, under that dungeon's ID.
2. **Per creature.** A run holds, per creature name, the number of kills and the XP they paid.
3. **Share of a level.** A run shows its kill XP as a percentage of a level.
4. **Run time.** A run's duration is the time from its first kill to its last kill, not from
   zoning in to zoning out. XP per hour is derived from it *(my call)*.
5. **A journal window** opened from a minimap button: runs grouped by dungeon on the left, the
   selected run's totals and creature table on the right.
6. **Blizzard's UI language.** The window's border, title bar, close button, insets, scroll bars,
   fonts and colours come from Blizzard's own templates and constants. No hand-drawn borders, no
   custom art.

## Non-goals

- Quest XP gained inside a dungeon. It is not recorded at all, not even on the side.
- Exploration XP, raids, battlegrounds and the open world *(my call)*.
- Party members' XP, loot, gold, sharing or exporting runs, comparing across characters
  *(my call)*.
- A per-kill log. Only per-creature totals are stored *(my call)*, so hundreds of runs stay small.

## Anti-goals

- A window that looks like an addon's: flat or blank borders, custom textures, non-Blizzard fonts.
- A percentage that lies when you level up mid-run.
- A corpse run or a disconnect splitting one run into two.

## Constraints

- Forever runs the Midnight addon API. Values can be secret inside instances; the addon never
  compares, does arithmetic on or branches on a secret value (`issecretvalue` first).
- Everything in "What the client gives us" is from Blizzard's source for this build, not from the
  game. The first dungeon run with the addon is the test; the addon logs what it saw.
- Repo conventions in `CLAUDE.md` apply (Lua 5.1, `ns`, no globals beyond prefixed required ones,
  `ns.log`, StyLua, TOC checks).

## What the client gives us (from the source, unverified in game)

- `CHAT_MSG_COMBAT_XP_GAIN` carries the "X dies, you gain N experience" text. It is **not** among
  the chat events flagged `SecretInChatMessagingLockdown` (party chat, monster yells and so on
  are), so the docs say it is readable in a dungeon. Its `text` is not marked `NeverSecret`
  either, so the code must still check.
- `UnitXP("player")` and `UnitXPMax("player")` are confirmed in game to be readable in and out of
  combat (CLAUDE.md, 9 November 2026). `PLAYER_XP_UPDATE` fires when XP changes.
- `GetInstanceInfo()` returns `name`, `instanceType` (`"party"` for a 5-player dungeon) and
  `instanceID`, which is the same for every run of a dungeon. The client gives no ID for an
  individual run.
- `SharedUIPanelTemplates.xml` has `ButtonFrameTemplate`, `PortraitFrameTemplate`,
  `DefaultPanelTemplate` and `InsetFrameTemplate`; the scroll system has `WowScrollBoxList`,
  `MinimalScrollBar`, `ScrollUtil.InitScrollBoxListWithScrollBar` and `CreateDataProvider`.
- Forever's minimap has Blizzard's addon compartment (`Blizzard_Minimap/Camelot/AddonCompartment`).
- *(Added in planning.)* `CHAT_MSG_SYSTEM` is flagged `SecretInChatMessagingLockdown`, so a reset
  message can't be read inside a dungeon, only outside. `UnitGUID` is documented secret for a
  unit that "isn't player-controlled or in the party/raid" while restrictions apply, so the copy
  number may be unreadable for dungeon creatures and the fallback rule may be the one in use.
- *(Added in planning.)* The client's global strings (kill and reset message formats) are in no
  file under `.cache/`; they can only be read in game.

## Confirmed in game (2026-11-12)

Deadmines twice and Ruins of Lordaeron, 371 kills, no Lua errors or blocked actions.

- The kill message's text is readable in a dungeon in combat. All 371 kills parsed, none secret,
  none unparsed. The only format seen was `COMBATLOG_XPGAIN_FIRSTPERSON_GROUP`; its first number
  is what lands on the bar. "You gain 3900 experience." was read as a non-kill gain and ignored.
- The message comes before the `PLAYER_XP_UPDATE` for the same kill. A level-up mid-run came as
  one update and was recorded.
- A reset started a new run (`openedBy = "reset"`).
- No run got a copy number, so creature GUIDs were most likely secret and the fallback rule is
  the one in use. The `PROBE guid` lines that would say so were pushed out of the capped log.
- Not yet seen: a rested-bonus kill, a corpse run, the `strings` lines, and the user's verdict on
  the window's look.

## Behaviour

### What counts

- Only while `GetInstanceInfo()` reports `instanceType == "party"` *(my call)*.
- Only the player's own XP from a creature kill, rested bonus included, since that is what lands
  on the bar *(my call)*. A gain that names no creature (quest, exploration) is ignored.

### Reading a kill

The primary source is the `CHAT_MSG_COMBAT_XP_GAIN` text, matched against patterns built from the
client's own format strings (the `COMBATLOG_XPGAIN_*` family), never hard-coded English, so it
works in every locale. The planner must find those strings and their variants (plain, rested
bonus, group bonus, penalties) in the client and build one matcher per variant. The matcher is a
pure function, apart from event code, returning creature name and total XP gained.

The format strings are not in `.cache/` (GlobalStrings aren't part of the UI source), so they
must come from the game *(my call)*: the build's first task is a `Dev/` probe that logs every
global whose name starts with `COMBATLOG_XPGAIN` or contains `INSTANCE_RESET`, with its value.
*(Amended while building: the matchers are built at load from every `COMBATLOG_XPGAIN*` global
the client defines, so no separate probe trip is needed; the probe's lines confirm the rule.)*
The user reloads twice, and the matcher is written against what the devlog shows, not against
Retail or Classic strings from memory.

**When the text is readable but matches no creature variant** (a quest or exploration gain): the
event is ignored.

**When the text is secret** *(my call)*: a kill message can't be told from another gain on the
same event, so every such event inside the dungeon is counted as one kill, under "Unknown
creatures". The message carries no amount, so the XP comes from the XP bar *(amended in the step
review)*: the unknown bucket holds what the bar gained while the run was recorded minus what
readable messages explain. Nothing is paired in time, so the order of the events doesn't matter.
The run is marked approximate in the saved data, and the window's detail header says
"Approximate: creature names were hidden", since a quest turn-in or another gain inside the
dungeon may then be counted. The run stores how many kills were read each way.

### Share of a level

Each gain is converted when it is recorded: `xp / UnitXPMax("player")` at that moment, summed over
the run *(my call)*. Before a level-up the gain is measured against the old level's size, after
it against the new one's, so the percentage is honest across a ding. The run also stores the
level at its first kill, shown in the detail header.

### Runs

The user's rule: **a new dungeon ID means a new run.** `GetInstanceInfo()`'s `instanceID` is per
dungeon, not per run, so the ID that carries this rule is the instance copy number inside a
creature's GUID (`Creature-0-<server>-<instanceID>-<zoneUID>-<npcID>-<spawnUID>`, the `zoneUID`
field), which differs between copies of the same dungeon.

- Entering a party instance, the addon looks for the copy number from any creature GUID it can
  read (target, mouseover, nameplates; the builder picks the sources and verifies each API). The
  GUID may be secret (`UnitGUID` is `SecretWhenUnitIdentityRestricted`), so it is checked with
  `issecretvalue` and never parsed when secret.
- **Copy number known:** the same number as that dungeon's open run continues it; a different
  number starts a new run. Kills that arrive before the number is known *(as built: stay in the run the fallback rule
  chose, and that run is merged into the matching one once the number is read)* are held in a pending
  run and attached once it is *(my call)*.
- **Copy number unreadable (fallback, agreed with the user):** the way the player left decides.
  Re-entering as a ghost or after dying, and a `/reload` or reconnect inside, continue the run.
  Walking out alive and back in starts a new run. A seen reset message (matched against the
  client's format string) or more than 30 minutes since the run's last kill also starts a new
  run *(my call)*. Known cost: a vendor trip mid-run splits the run.
- The run stores which rule opened it, so a wrong split can be traced.
- There is one open run per dungeon, not one overall: going from dungeon A to B and back to A
  continues A's run under the same rules.
- A run is numbered per dungeon and character, starting at 1 ("Run 3").
- A run with no kills is never saved.
- `/reload` or a relog inside the dungeon continues the open run; the open run lives in the saved
  data, not only in memory.
- A run is "finished" implicitly: nothing closes it, it simply stops receiving kills.

### Storage

- Per character, kept until the player deletes it *(my call)*. *(Amended in planning: stored in
  one account-wide table with a section per `"Name-Realm"`, the repo's existing pattern, instead
  of `SavedVariablesPerCharacter`. The window still shows only the current character.)*
- Layout is the builder's to design, with a `DB_VERSION` and a migration path from day one. Per
  run it must hold: dungeon `instanceID` and name, run number, start level, first and last kill
  time, total kill XP, total share of a level, and per creature the kill count and XP.
- "XP each" in the creature table is total divided by kills, since the same creature can pay
  different amounts *(my call)*.

## The window

Agreed with the user from a wireframe on 2026-11-12.

- One window, built on Blizzard's standard panel template with its title bar and close button,
  titled "Dungeon experience journal". It behaves like Blizzard's panels: Escape closes it, it
  can be opened in combat (it holds no secure frames) *(my call)*.
- **Left: run list**, in an inset with a Blizzard scroll box. Runs are grouped under a header per
  dungeon ("The Deadmines · 3 runs"), newest run first, the most recently run dungeon first. A
  row shows "Run N · date", the share of a level on the right, and beneath it
  "7,380 XP · 96 kills · 38 min". The selected row uses Blizzard's list highlight.
- **Right: run detail.** A header line ("The Deadmines · run 3 · level 19"), then five totals:
  kill XP, share of a level, kills, time, XP per hour. Then a scrolling creature table with
  columns Creature, Kills, XP each, Total, sorted by total XP, highest first *(my call)*.
- **Deleting:** right-clicking a run opens Blizzard's context menu (`MenuUtil`) with "Delete run"
  *(my call)*. No confirmation dialog; it's one run.
- **Empty state:** with no runs, the list is empty and the detail side says
  "Run a dungeon to start your journal." *(my call)*
- Numbers use `BreakUpLargeNumbers`. Text uses Blizzard's font objects and colour constants.
  Strings are plain ASCII where the client font may lack a glyph (the "·" in this document is a
  placeholder; the builder picks a separator the client font has).
- The window opens on the run being recorded if it has kills, else on the newest run *(my call)*.

### Opening it

- **Minimap button.** A round minimap button, left-click toggles the window, dragging moves it
  around the minimap's edge. *(Amended while building: hand-built from Blizzard's minimap-button
  art (`MiniMap-TrackingBorder`, `UI-Minimap-Background`, the zoom button's highlight) at
  LibDBIcon's size, not with LibDBIcon. That library and the two it needs are published as SVN
  repositories, and `scripts/libs.sh` fetches git only; changing the repo's tooling for one
  button wasn't worth it. Cost: addons that only list LibDataBroker launchers won't show it.)*
- **Addon compartment entry** in Blizzard's minimap dropdown, same action *(my call)*.
- **Slash command** `/fdxp`, same action *(my call)*.

This is the user's decision against the workflow's "native, not standalone" default: the journal
has no Blizzard window to live in, so it gets its own, on the condition in Goal 6.

## In-game checks

Each has a log line so one run answers it (`scripts/devlog.sh --addon ForeverDungeonXP`).

| Question | Tag | Expected |
| --- | --- | --- |
| Is the kill message's text readable in a dungeon? | `KILL` | text not secret, creature and XP parsed |
| Do all message variants parse (rested, group)? | `KILL` | no `unparsed` lines |
| Does the fallback path trigger? | `KILL` | no `KILL secret` lines (each carries the run's `fallback` count) |
| What does `GetInstanceInfo()` return on entry? | `RUN` | `party`, a stable `instanceID` |
| Is a creature's GUID readable in a dungeon, in and out of combat? | `PROBE` | not secret, a `zoneUID` field |
| Does the copy number change after a reset and stay the same on re-entry? | `RUN` | `RUN copy new` / `copy same` / `copy unchanged` / `copy stamp` |
| Which global strings hold the kill and reset messages? | `PROBE` | the `COMBATLOG_XPGAIN*` and reset strings with values |
| Is the reset message seen by a non-leader? | `RUN` | a `reset` line after a reset |
| Does re-entry continue the run? | `RUN` | `continue` after a corpse run |

## Left to the builder

- File and module split, the SavedVariables layout, the exact templates and font objects (verify
  each in `.cache/wow-ui-source` first), the minimap icon (a Blizzard icon texture), the window's
  size, and whether the window is XML or Lua.
- Where the open-run decision is made (`PLAYER_ENTERING_WORLD` or another event), checked against
  how the client reports instance changes on login and `/reload`.

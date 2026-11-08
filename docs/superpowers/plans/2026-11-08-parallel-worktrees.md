# Parallel worktrees in game

**Goal:** several worktrees test their own addons in game at the same time (e.g. a Professions
session tested while crafting, another addon while questing) without relinking, and their devlogs
don't push each other out. Agreed with the user in chat on 8 November 2026; a small change, so no
spec.

**Limit:** WoW loads one folder per addon name, so two worktrees can't load the *same* addon at
once.

## Tasks (one PR, `feat(scripts,foreverdev): ...`)

1. **`scripts/worktree.sh`: per-addon claims.**
   - `game [Addon...]` links only the named addons, by default the ones this branch changed
     against `origin/main` (committed, staged, unstaged and untracked under `addons/`). Every
     other link stays. It stops, before changing any link, if another live worktree holds one of
     them, and names that worktree. Links into a removed worktree (dangling) are free.
   - `restore` hands this worktree's links back to the main checkout (an addon main doesn't have
     is unlinked).
   - `reset` (any checkout, main included) points every link into this repo back at main, and
     removes links dangling into a removed worktree.
   - `status` labels each link's checkout (`main` or the worktree's folder name).
2. **ForeverDev: per-addon log caps.** `MAX_ENTRIES` becomes a cap per addon (log and blocked
   entries by `entry.addon`, errors by the `AddOns/<Name>/` in their message, else one shared
   bucket), so a chatty addon only drops its own oldest lines. Same flat `entries` layout, so no
   SavedVariables change. Eviction compacts in one pass once a bucket runs a slack over its cap,
   not on every line. `/fdev clear <addon>` clears one addon's entries and LogOnce/LogChanged
   memory; bare `/fdev clear` still clears all.
3. **`scripts/devlog.sh`: worktree default.** In a worktree that holds links, it shows only the
   addons it holds (`--addon` takes a comma list; `--all-addons` shows everything). When the
   latest session has nothing matching, it says which earlier session last had.
4. **Docs:** CLAUDE.md (commands, Worktrees), `docs/feature-workflow.md` Phase 0,
   `docs/bugfix-workflow.md`, README.

## Review focus

- Path comparisons on Windows junctions (`readlink` spelling vs `git worktree list`'s `C:/...`)
  and paths with spaces (`WOW_DIR`).
- `game` must check every conflict before touching any link.
- ForeverDev compaction: counts stay right after compaction, `/fdev clear <addon>` and the pending
  flush; `errorsBySignature` drops evicted errors.

## Reviewers

Core reviewers plus the shell reviewer (`scripts/`). No SavedVariables layout change, so no
`savedvariables-guard` (the `/fdev` slash command only gains an argument).

## In-game checks

- `scripts/worktree.sh game` in two worktrees with different addons: `status` shows both; both
  load after `/rl`; `reset` puts everything back on main.
- After `/rl`, `scripts/devlog.sh` in a worktree shows only its addons; `/fdev clear <addon>`
  leaves other addons' lines.

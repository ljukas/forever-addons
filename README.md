# forever-addons

Personal addons for World of Warcraft: Forever (interface 16001).

## Setup (once)

```sh
brew install stylua lua-language-server luajit
scripts/setup.sh   # fetch WoW API annotations + Blizzard's Forever UI source into .cache/
scripts/link.sh    # link addons/* into the game's _forever_/Interface/AddOns
```

`WOW_DIR` defaults to `/Applications/World of Warcraft/_forever_` on macOS and
`C:\Program Files (x86)\World of Warcraft\_forever_` on Windows. If the game lives somewhere
else, put `WOW_DIR="/path/to/World of Warcraft/_forever_"` in `.env.local`.

On Windows, run the scripts from Git Bash. They link folders with NTFS junctions (Git Bash's
`ln -s` would silently copy them), so neither admin rights nor Developer Mode is needed.

The game loads the main checkout's addons, so `git pull` there updates what's in game. To try a
branch before it's merged, run `scripts/worktree.sh game` in its worktree (it takes over only the
addons that branch changed), `/rl` in game, and `scripts/worktree.sh restore` when done.
`scripts/worktree.sh reset` points every addon back at the main checkout at once.

In game, enable **ForeverDev**. It gives you:

- `/rl` to reload the UI. There's also a "Reload UI" keybind (Key Bindings → AddOns) and a
  click target in the minimap addon compartment.
- Lua errors and blocked actions captured to disk, with the addons' log lines. Read them with
  `scripts/devlog.sh` (`--addon ForeverProfessions`, `--tag GATHER` to narrow it down). In a
  worktree it shows only the addons that worktree has in game.
- Evidence the addons keep across sessions, such as gathering spell IDs or DoT tick intervals.
  Read it with `scripts/observed.sh [Addon]` or `scripts/combat-knowledge.sh`.
- Probes of what the client restricts where (restriction states, secret unit values), logged
  on login, zone changes and target changes.
- `/fdev errors` lists this session's errors in chat. `/fdev clear` empties the log, and
  `/fdev clear <Addon>` only that addon's lines (each addon keeps its own last 500).
  `/fdev forget <Addon>` drops that addon's evidence.

## Day to day

```sh
scripts/new-addon.sh MyAddon   # new addon from template/, already linked into the game
scripts/lint.sh                # format + LuaLS + TOC checks (CI runs the same)
```

Edit, then `/rl` in game. New addon folders may need a client restart before they show up in
the AddOns list.

Claude works through `/feature-workflow`, `/bugfix-workflow` and `/refactor-workflow` (the
process is in [docs/](docs/feature-workflow.md)), each in its own worktree under
`.claude/worktrees/`. To try a worktree's version in game, run `scripts/worktree.sh game` from it
and `/rl`. Each worktree takes over only its own addons, so two sessions on different addons can
both be live in game. `scripts/worktree.sh restore` hands a worktree's addons back to the main
checkout, and `scripts/worktree.sh reset` hands back all of them.

VS Code: install the recommended extensions (LuaLS, StyLua). `.luarc.json` already points LuaLS
at the WoW API annotations in `.cache/`.

## After a game patch

1. **Refresh the API reference:** run `scripts/setup.sh`. It updates the Blizzard source to
   the new build and prints the client's interface number.
2. **Check the interface number:** run `scripts/lint.sh`. If the patch changed the interface
   (for example `16001` → `16002`), lint fails on every TOC. Update `## Interface:` in every
   `addons/*/*.toc` and in `template/Addon/__ADDON__.toc`.

## Commits and pull requests

Every change goes through a pull request whose title is a
[Conventional Commit](https://www.conventionalcommits.org/), e.g.
`feat(foreverprofessions): show node counts on the world map`. PRs are squash-merged, so each one
becomes a single commit on `main`. CI checks the title. See
[CLAUDE.md](CLAUDE.md#commits-and-pull-requests) for the types and scopes.

## Releasing

Merge a PR that renames `## Unreleased` to `## vX.Y.Z` in the addon's `CHANGELOG.md`, then tag
`<Addon>-vX.Y.Z` on `main` and push the tag. GitHub Actions packages the addon with the BigWigs
packager and creates a GitHub release. See [CLAUDE.md](CLAUDE.md#releasing-an-addon) for
CurseForge/Wago.

## License

[MIT](LICENSE).

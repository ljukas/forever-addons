# forever-addons

Personal addons for World of Warcraft: Forever (interface 16001).

## Setup (once)

```sh
brew install stylua lua-language-server luajit
scripts/setup.sh   # fetch WoW API annotations + Blizzard's Forever UI source into .cache/
scripts/link.sh    # symlink addons/* into /Applications/World of Warcraft/_forever_/Interface/AddOns
```

If the game lives somewhere else, put `WOW_DIR="/path/to/World of Warcraft/_forever_"` in `.env.local`.

In game, enable **ForeverDev**. It gives you:

- `/rl` to reload the UI. There's also a "Reload UI" keybind (Key Bindings → AddOns) and a
  click target in the minimap addon compartment.
- Lua errors and blocked actions captured to disk, with the addons' log lines. Read them with
  `scripts/devlog.sh` (`--addon ForeverProfessions`, `--tag GATHER` to narrow it down).
- Evidence the addons keep across sessions, such as gathering spell IDs or DoT tick intervals.
  Read it with `scripts/observed.sh [Addon]` or `scripts/combat-knowledge.sh`.
- Probes of what the client restricts where (restriction states, secret unit values), logged
  on login, zone changes and target changes.
- `/fdev errors` lists this session's errors in chat. `/fdev clear` empties the log.
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
and `/rl`. `scripts/worktree.sh restore` points the game back at the main checkout.

VS Code: install the recommended extensions (LuaLS, StyLua). `.luarc.json` already points LuaLS
at the WoW API annotations in `.cache/`.

## Launch-day checklist (WoW Forever launches 4 November 2026)

This repo was set up while the Forever beta was closed. Nothing in it has run in the game
yet. Until launch, the only checks are `scripts/lint.sh` and Blizzard's Forever UI source
in `.cache/`. Runtime behaviour (event timing, return values, layout, taint) is unverified.

On launch day, before testing any real addon:

1. **Refresh the API reference:** run `scripts/setup.sh`. It updates the Blizzard source to
   the release build and prints the client's interface number.
2. **Check the interface number:** run `scripts/lint.sh`. If launch changed the interface
   (for example `16001` → `16002`), lint fails on every TOC. Update `## Interface:` in every
   `addons/*/*.toc` and in `template/Addon/__ADDON__.toc`.
3. **Re-link the addons:** run `scripts/link.sh`. Then start the game and confirm
   **ForeverDev** shows up in the AddOns list. If it doesn't appear even after a full client
   restart, the client may not follow symlinked folders. Ask Claude to switch `link.sh` to
   copying files instead.
4. **Try ForeverDev in game:**
   - `/rl` reloads the UI.
   - `/fdev` prints the session number and the list of commands.
   - Bind *Key Bindings → AddOns → Reload UI* to a key and check it works.
   - Click ForeverDev in the minimap addon compartment. It should reload the UI.
5. **Check error capture:** run `/run error("devlog test")`, close the error popup, then
   `/rl`. Ask Claude to run `scripts/devlog.sh`. It should show the session with the
   `devlog test` error and a stack trace.
6. **Report problems:** tell Claude about anything that failed, so the tooling gets fixed
   before you rely on it for real addons. Then delete this section.

## Commits and pull requests

Every change goes through a pull request whose title is a
[Conventional Commit](https://www.conventionalcommits.org/), e.g.
`feat(forevermap): show node counts on the world map`. PRs are squash-merged, so each one
becomes a single commit on `main`. CI checks the title. See
[CLAUDE.md](CLAUDE.md#commits-and-pull-requests) for the types and scopes.

## Releasing

Merge a PR that renames `## Unreleased` to `## vX.Y.Z` in the addon's `CHANGELOG.md`, then tag
`<Addon>-vX.Y.Z` on `main` and push the tag. GitHub Actions packages the addon with the BigWigs
packager and creates a GitHub release. See [CLAUDE.md](CLAUDE.md#releasing-an-addon) for
CurseForge/Wago.

## License

[MIT](LICENSE).

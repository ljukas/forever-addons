# forever-addons

Monorepo of self-made addons for **World of Warcraft: Forever** (Vanilla-era content on the
modern client). Claude writes most of the code; the user tests in game.

**Process lives in `docs/{feature,refactor,bugfix}-workflow.md`**, runnable as `/feature-workflow <idea>`,
`/refactor-workflow <target>` and `/bugfix-workflow <symptom>` (thin skills in `.claude/skills/` that
load the doc). Every one starts in a fresh worktree from `origin/main` (see "Worktrees" below).

## The Forever client

- Interface **16001** (client 1.60.x). TOCs use `## Interface: 16001`; `scripts/lint.sh` fails if
  a TOC doesn't include the current client's interface.
- Game type `forever`, alias `camelot`, in the `mainline` family. Blizzard's own code puts
  Forever-specific variants in `Camelot/` subfolders. Optional per-flavor TOC suffix: `_Camelot.toc`.
- It runs the **modern (Midnight 12.x) addon API**, not the Classic Era API. That includes
  Midnight's combat restrictions: many unit/combat APIs return *secret values* that tainted
  (addon) code can pass along but not compare, do arithmetic on or branch on. Use
  `issecretvalue(v)` when unsure. The API docs flag these with `SecretReturns = true` /
  `SecretArguments = ...`.
- Do not assume a Retail or Classic API exists or behaves the same way. Verify it in
  `.cache/wow-ui-source` (below).

**Not yet verified in game.** Forever launches 4 November 2026, and until then nothing here
(ForeverDev, the devlog loop or any addon) has run in the client. Treat lint and
`.cache/wow-ui-source` as the only checks, and say plainly what is untested. If the user
reports launch-day results, work through the checklist in README.md.

## Looking up the API (do this before using any API you haven't verified)

`scripts/setup.sh` fetches reference material into `.cache/` (gitignored; lint runs it if missing):

| Path | What | Use for |
| --- | --- | --- |
| `.cache/wow-ui-source/Interface/AddOns/Blizzard_APIDocumentationGenerated/` | Blizzard's generated API docs **for this exact Forever build** | `C_*` functions, events, enums, widget methods, secret flags |
| `.cache/wow-ui-source/Interface/AddOns/Blizzard_*/` | Blizzard's Forever UI source (Lua + XML) | FrameXML globals, mixins, templates, how Blizzard does it |
| `.cache/wow-api/Annotations/Core/` | Ketho's LuaLS annotations (Retail-based) | Types for LuaLS; may lack or differ for Forever-only APIs |
| `types/forever.lua` | Our own `---@meta` annotations | Add Forever-only APIs here once verified, to silence LuaLS |

Handy searches:

```sh
D=.cache/wow-ui-source/Interface/AddOns/Blizzard_APIDocumentationGenerated
grep -rl 'Namespace = "C_Timer"' $D                # find a namespace's doc file
grep -rn -A15 'Name = "After",' $D/UITimerDocumentation.lua   # function signature
grep -rn -B2 -A12 'LiteralName = "PLAYER_LOGIN"' $D     # event payload
grep -rn 'function EventUtil\.' .cache/wow-ui-source/Interface/AddOns/Blizzard_SharedXML/
```

## Layout

- `addons/<Name>/` – one addon per folder; the folder name must equal the TOC name (`<Name>.toc`).
  PascalCase names.
- `addons/ForeverDev/` – dev-only helper addon, **never released** (see the feedback loop below).
- `template/Addon/` – scaffold used by `scripts/new-addon.sh` (`__ADDON__` is replaced).
- `scripts/` – all tooling, see below. `scripts/lib.sh` holds shared helpers and `WOW_DIR`.
- `types/` – extra LuaLS annotations.

## Commands

```sh
scripts/new-addon.sh MyAddon        # scaffold addons/MyAddon from the template and symlink it into the game
scripts/lint.sh                     # StyLua check + LuaLS diagnostics + TOC checks. Run after every change.
stylua addons template types        # auto-format
scripts/link.sh                     # (re)symlink every addon into _forever_/Interface/AddOns
scripts/devlog.sh [--errors] [--all] [--addon NAME] [--tag TAG]  # print what ForeverDev captured in game (errors, taint, logs)
scripts/observed.sh [Addon] [filter] # print the evidence addons keep through ForeverDev (e.g. ForeverProfessions' gathers)
scripts/combat-knowledge.sh [spell] # print what ForeverCombat observed about DoTs/HoTs (IDs, ticks, intervals, misses)
scripts/package.sh MyAddon [v1.0.0] # build the release zip locally into .release/MyAddon/
scripts/check-pr-title.sh "<title>" # check a PR title is a Conventional Commit (CI runs it on every PR)
scripts/setup.sh                    # refresh .cache/ (run after a game patch)
scripts/worktree.sh <command>       # setup, game, restore or status: share .cache/ with a worktree, move the game's addon links to it and back
```

`WOW_DIR` defaults to `/Applications/World of Warcraft/_forever_`. Override it in `.env.local`.

## Feedback loop with the game

Addons are symlinked into the game, so there is no copy or build step:

1. Claude edits the code and runs `scripts/lint.sh` until it's clean.
2. The user types `/rl` (or uses the ForeverDev keybind or addon compartment entry) in game.
   `/reload` picks up Lua/XML/TOC edits and new files listed in the TOC. A **brand-new
   addon folder** may need a full client restart before it shows in the AddOns list.
3. Claude runs `scripts/devlog.sh` to read the Lua errors, `ADDON_ACTION_BLOCKED/FORBIDDEN`
   (taint) events and `ns.log(...)` lines from that session, and `scripts/observed.sh` for
   the evidence kept across sessions.

SavedVariables (and so the devlog) are only written on `/reload`, logout or exit. To see
the result of a test, ask the user to `/rl` *after* doing it. Instrument code with
`ns.log(...)` rather than `print` when Claude needs to see the output.

## Logging, probing and evidence

All of it goes through ForeverDev's API (`addons/ForeverDev/ForeverDev.lua`), so released
addons carry no dev code beyond the shim at the top of their `Core.lua` (from the template):
`ns.dev` is ForeverDev's logger for the addon, or an inert stand-in (`ns.Inert`) whose calls
do nothing and return nil when ForeverDev isn't loaded (`ns.dev.enabled` is false).

- `ns.log(TAG, ...)` logs a line. `TAG` is one upper-case word (`TICK`, `GATHER`, `PROBE`) that
  `devlog.sh --tag` filters on. Each addon lists its tags, by file, in the shim's comment.
- `ns.dev:LogOnce(key, TAG, ...)` logs once per session and key, and
  `ns.dev:LogChanged(key, value, TAG, ...)` only when `value` differs from the last one. Use
  them instead of hand-rolled "already logged" flags.
- **Evidence** (what the addon saw in game, kept across sessions) goes in
  `ns.dev:Observed(defaults, category, key, ...)`, a table in `ForeverDevDB.observed[addon]`,
  with `ForeverDev.Count`, `Extend` and `Sample`. Each addon keeps it in a `Knowledge.lua` that
  documents the layout and starts with
  `if not ns.dev.enabled then ns.Knowledge = ns.Inert() return end`, so for players every
  `ns.Knowledge` function does nothing. `/fdev forget <Addon>` drops the evidence once the
  data it checked has been corrected.
- **Probes** that only log go in `addons/<Name>/Dev/`, listed in the TOC between
  `#@do-not-package@` lines and ignored in `.pkgmeta`, so releases leave them out. They start
  with `if not ns.dev.enabled then return end`. Probes that hold for every addon (restriction
  states, which unit values are secret) belong in `addons/ForeverDev/Probes.lua`.
- Code that always runs may call `ns.log` and any `ns.dev` method, but must not use their
  results, and work done only to feed a log line goes inside `if ns.dev.enabled then`.
  `Observed` and the `ForeverDev.*` helpers (`Situation`, `SecretNames`, `Describe`, `Count`,
  ...) are only for code that runs with ForeverDev: `Dev/` files and enabled `Knowledge.lua`.

## Worktrees

Several Claude sessions work in this repo at once, so all work happens in a worktree, never in
the main checkout: `EnterWorktree` (creates `.claude/worktrees/<name>` from `origin/main`), rename
the branch to `<type>/<slug>`, then `scripts/worktree.sh setup` to link `.cache/` and `.env.local`
from the main checkout. The game's AddOns links point at one checkout at a time, the main one by
default. `scripts/worktree.sh game` points them at the current worktree for in-game testing, and
`scripts/worktree.sh restore` hands them back. Run `restore` before removing the worktree.

## Code conventions

- WoW runs **Lua 5.1**: no `goto`, no `//` or bitwise operators (use `bit.band` etc.), no
  integer type. WoW adds `strsplit`, `strtrim`, `wipe`, `tinsert`, `CopyTable`, `Mixin`, etc.
- Each file starts with `local ADDON_NAME, ns = ...` and shares state through `ns` (ForeverDev,
  which exposes its API as the `ForeverDev` global instead, takes only `ADDON_NAME`). Create no
  globals except SavedVariables and names the client requires (`SLASH_*`, `BINDING_*`,
  TOC-referenced functions). Prefix all of those with the addon name.
- An addon other addons build on exposes its API as one global named after it, defined last
  in its `API.lua`: `ForeverProfessions` records gathers and skills, and ForeverMap draws them
  through it. The dependent lists it under `## Dependencies:` and calls the API from its own
  `ADDON_LOADED` on, never the provider's `ns`.
- Prefer modern client facilities over libraries: `EventUtil.ContinueOnAddOnLoaded`,
  `EventRegistry`, `CreateFrame` with mixins, `C_Timer`, `Settings` (options panels),
  `MenuUtil` (context menus). The repo uses no Ace3 or libs by default. If one is needed, add
  it per addon via `.pkgmeta` externals.
- Guard protected actions with `InCombatLockdown()`, and never touch secure frames in combat.
- Every new Lua/XML file must be listed in the TOC (or included from XML). Lint checks this.
- StyLua formats with tabs and a 120-column limit. `.editorconfig` covers the rest.
- CodeRabbit runs luacheck on every PR (`.luacheckrc`): unused variables and arguments,
  shadowing, and globals assigned by accident. A new intentional global (SavedVariables, a mixin
  named in XML, `SLASH_*`, `BINDING_*`) goes in that addon's `globals` list there. Check locally
  with `luacheck addons template` (`brew install luacheck`).

## Commits and pull requests

Commits follow [Conventional Commits](https://www.conventionalcommits.org/):
`type(scope)!: description`.

- **Types:** `feat` (new behaviour players notice), `fix`, `perf`, `refactor`, `docs`, `style`,
  `test`, `build`, `ci`, `chore`, `revert`.
- **Scopes:** the addon folder name in lowercase (`forevermap`, `foreverprofessions`,
  `forevercombat`, `foreverdev`),
  or `ci`, `scripts`, `template`, `types`, `deps`. Separate several with commas. Leave the
  scope out for repo-wide changes.
- **Description:** imperative, lowercase start, no trailing period. Keep the whole title within
  72 characters.
- **Breaking changes:** add `!` after the scope, or a `BREAKING CHANGE:` footer, when a change
  breaks players' SavedVariables, settings or slash commands.

Every change goes through a pull request. Work on a branch, never on `main`; the branch's
commits are conventional too.

- PRs are **squash-merged**, so `main` gets one commit per PR. Its title is the PR title plus
  ` (#N)`, and its body lists the branch's commit messages. Merge commits and rebase merges
  are disabled, and merged branches are deleted.
- So the **PR title must be a Conventional Commit**. `.github/workflows/pr-title.yml` checks
  it with `scripts/check-pr-title.sh`. The PR description follows
  `.github/pull_request_template.md` (Summary, Testing).
- A `feat` or `fix` to an addon also adds a line under `## Unreleased` in that addon's
  `CHANGELOG.md`. The changelog is written for players, not copied from commits.

## Releasing an addon

1. On a branch, rename `## Unreleased` to `## vX.Y.Z` in `addons/<Name>/CHANGELOG.md` (the
   release notes are taken from that section). Open a PR titled
   `chore(<name>): release vX.Y.Z` and squash-merge it.
2. Tag the merged commit and push the tag:
   `git switch main && git pull && git tag <Name>-vX.Y.Z && git push origin <Name>-vX.Y.Z`.
   A `-betaN` / `-alphaN` suffix makes a pre-release.
3. `.github/workflows/release.yml` builds the zip with the BigWigs packager (`scripts/package.sh`)
   and attaches it to a GitHub release. CurseForge and Wago uploads also run once the TOC has
   `## X-Curse-Project-ID:` / `## X-Wago-ID:` and the repo has the `CF_API_KEY` /
   `WAGO_API_TOKEN` secrets.

Everything is MIT-licensed (`LICENSE`, and `## X-License: MIT` in each TOC). `package.sh` copies
`LICENSE` into every zip. Blizzard's add-on policy requires addons to be free and their code
readable: never obfuscate or minify.

The packager replaces `@project-version@` and strips `#@do-not-package@ … #@end-do-not-package@`
blocks. The template uses such a block to keep the dev-only `OptionalDeps: ForeverDev` out of
releases.

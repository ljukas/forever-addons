# forever-addons

Monorepo of self-made addons for **World of Warcraft: Forever** (Vanilla-era content on the
modern client). Claude writes most of the code; the user tests in game.

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
scripts/devlog.sh [--errors] [--all]  # print what ForeverDev captured in game (errors, taint, logs)
scripts/combat-knowledge.sh [spell] # print what ForeverCombat observed about DoTs/HoTs (IDs, ticks, intervals, misses)
scripts/package.sh MyAddon [v1.0.0] # build the release zip locally into .release/MyAddon/
scripts/check-pr-title.sh "<title>" # check a PR title is a Conventional Commit (CI runs it on every PR)
scripts/setup.sh                    # refresh .cache/ (run after a game patch)
```

`WOW_DIR` defaults to `/Applications/World of Warcraft/_forever_`. Override it in `.env.local`.

## Feedback loop with the game

Addons are symlinked into the game, so there is no copy or build step:

1. Claude edits the code and runs `scripts/lint.sh` until it's clean.
2. The user types `/rl` (or uses the ForeverDev keybind or addon compartment entry) in game.
   `/reload` picks up Lua/XML/TOC edits and new files listed in the TOC. A **brand-new
   addon folder** may need a full client restart before it shows in the AddOns list.
3. Claude runs `scripts/devlog.sh` to read the Lua errors, `ADDON_ACTION_BLOCKED/FORBIDDEN`
   (taint) events and `ns.log(...)` lines from that session.

SavedVariables (and so the devlog) are only written on `/reload`, logout or exit. To see
the result of a test, ask the user to `/rl` *after* doing it. Instrument code with
`ns.log(...)` (from the template) rather than `print` when Claude needs to see the output.
It is a no-op when ForeverDev isn't loaded.

## Code conventions

- WoW runs **Lua 5.1**: no `goto`, no `//` or bitwise operators (use `bit.band` etc.), no
  integer type. WoW adds `strsplit`, `strtrim`, `wipe`, `tinsert`, `CopyTable`, `Mixin`, etc.
- Each file starts with `local ADDON_NAME, ns = ...` and shares state through `ns`. Create no
  globals except SavedVariables and names the client requires (`SLASH_*`, `BINDING_*`,
  TOC-referenced functions). Prefix all of those with the addon name.
- Prefer modern client facilities over libraries: `EventUtil.ContinueOnAddOnLoaded`,
  `EventRegistry`, `CreateFrame` with mixins, `C_Timer`, `Settings` (options panels),
  `MenuUtil` (context menus). The repo uses no Ace3 or libs by default. If one is needed, add
  it per addon via `.pkgmeta` externals.
- Guard protected actions with `InCombatLockdown()`, and never touch secure frames in combat.
- Every new Lua/XML file must be listed in the TOC (or included from XML). Lint checks this.
- StyLua formats with tabs and a 120-column limit. `.editorconfig` covers the rest.

## Commits and pull requests

Commits follow [Conventional Commits](https://www.conventionalcommits.org/):
`type(scope)!: description`.

- **Types:** `feat` (new behaviour players notice), `fix`, `perf`, `refactor`, `docs`, `style`,
  `test`, `build`, `ci`, `chore`, `revert`.
- **Scopes:** the addon folder name in lowercase (`forevermap`, `forevercombat`, `foreverdev`),
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

The packager replaces `@project-version@` and strips `#@do-not-package@ … #@end-do-not-package@`
blocks. The template uses such a block to keep the dev-only `OptionalDeps: ForeverDev` out of
releases.

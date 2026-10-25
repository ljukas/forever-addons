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
- Lua errors and blocked actions captured to disk. Read them with `scripts/devlog.sh`.
- `/fdev errors` lists this session's errors in chat. `/fdev clear` empties the log.

## Day to day

```sh
scripts/new-addon.sh MyAddon   # new addon from template/, already linked into the game
scripts/lint.sh                # format + LuaLS + TOC checks (CI runs the same)
```

Edit, then `/rl` in game. New addon folders may need a client restart before they show up in
the AddOns list.

VS Code: install the recommended extensions (LuaLS, StyLua). `.luarc.json` already points LuaLS
at the WoW API annotations in `.cache/`.

## Releasing

Tag `<Addon>-vX.Y.Z` and push it. GitHub Actions packages the addon with the BigWigs
packager and creates a GitHub release. See [CLAUDE.md](CLAUDE.md#releasing-an-addon) for
CurseForge/Wago.

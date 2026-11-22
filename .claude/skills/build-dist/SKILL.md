---
name: build-dist
description: Minify the Jukes WoW addons from build/ (source) into dist/ (minified, comment-free Lua). Use whenever creating a build/dist, minifying the addons, or as the first step of a release.
---

# Build → Dist (minify)

The three stages in this repo:

| Stage | Folder | What it is |
| --- | --- | --- |
| Build | `build/` | The source. Runs locally in WoW. Never minify or edit it here. |
| **Dist** | `dist/` | Minified copy of each addon (this skill). Git-ignored. |
| Release | `JukesCurse/` | Zips + screenshots to upload to CurseForge (`curse-release` skill). |

## Run

```bash
python3 .claude/skills/build-dist/scripts/dist.py
```

Wipes `dist/` and writes `dist/<Addon>/` for every `build/<Addon>/` that has a
`<Addon>.toc` (so `JukesScreenshots` is skipped).

## What it does

- **Lua:** strips all comments (`--`, `--[[ ]]`, `--[==[ ]==]`) and every
  space/newline not needed to separate tokens. Strings, long strings and
  numbers are kept byte-for-byte. Locals/globals are **not** renamed: WoW addons
  depend on global names, SavedVariables and frame names.
- **Safety check:** each minified file is re-tokenized and must give exactly
  the same tokens as the source without comments, otherwise it fails. `luac -p`
  is also run if installed (Homebrew's is newer than WoW's Lua 5.1, so its
  complaints are printed as notes only).
- **.toc:** keeps `##` metadata and the file list, drops `#` comments and blank
  lines. Other files are copied unchanged.

## After running

Report the size table the script prints. Note that in-game Lua errors from
minified code all point at line 1; reproduce bugs with the `build/` source.

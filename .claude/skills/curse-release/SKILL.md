---
name: curse-release
description: Prepare a CurseForge release of the Jukes WoW addons - minify build/ into dist/, then zip each addon and gather its screenshots into JukesCurse/ ready to upload. Use when preparing a release, making release zips, or staging uploads for CurseForge/GitHub.
---

# Release (CurseForge staging)

The three stages in this repo:

| Stage | Folder | What it is |
| --- | --- | --- |
| Build | `build/` | The source. Runs locally in WoW. |
| Dist | `dist/` | Minified code (`build-dist` skill). |
| **Release** | `JukesCurse/` | Zipped dist + screenshots to upload to CurseForge (this skill). |

`dist/` and `JukesCurse/` are git-ignored and fully regenerated on each run.

## Before running

If this is a real release, check each changed addon's `## Version:` in
`build/<Addon>/<Addon>.toc` has been bumped — the zip names come from it. Ask
the user for the release tag (e.g. `v1.5.0`) if they haven't given one; the
latest existing tag is `git describe --tags --abbrev=0`.

## Run

```bash
python3 .claude/skills/curse-release/scripts/release.py --tag vX.Y.Z
```

This runs the dist step first (`--skip-dist` reuses the existing `dist/`).
Omit `--tag` for a `-dev` all-in-one zip.

## Output

`JukesCurse/` is **flat** — no subfolders, every file directly inside it:

```
JukesCurse/
  JukesAddons-all-<tag>.zip     all addons (GitHub release)
  <Addon>-v<Version>.zip        upload as the CurseForge file
  <addon-prefix>-*.jpg|png      screenshots, upload to the project's Images
```

Screenshots come from `build/JukesScreenshots/<Addon without "Jukes">/`
(e.g. `JukesTargetor` → `Targetor/`). Their file names are already prefixed
per addon (`targetor-`, `gold-audit-`, `scale-counts-`); keep new ones
prefixed too, since a duplicate name stops the release. Mention any addon
with no screenshots to the user.

## After running

Report the zips, the screenshots grouped by addon, any addon without
screenshots, and the full path `JukesCurse/` so the user can open it for
uploading.

## Upload to CurseForge (only when asked)

All files go to one CurseForge project (id 1808490, set in `upload.py`).
The token is `CURSEFORGE_API_TOKEN` in the git-ignored `.env` at the repo root.

```bash
python3 .claude/skills/curse-release/scripts/upload.py --tag vX.Y.Z --dry-run
python3 .claude/skills/curse-release/scripts/upload.py --tag vX.Y.Z
```

- Each `<Addon>-v<Version>.zip` goes up as a normal file. This site rejects
  "additional files".
- `JukesAddons-all-<tag>.zip` is for GitHub only: **never upload it to CurseForge**.
- Game version: newest **WoW Forever** version on CurseForge, looked up each run.
- Release type `release`; changelog = commit subjects since the previous tag
  (`--changelog-file` to override).

Always run `--dry-run` first and show the user the changelog and file list;
upload only after they confirm. Uploads are public and can't be undone via
the API. Screenshots can't go through the API. Use the project's Media tab
(`https://authors.curseforge.com/#/projects/1808490/media`): upload the new or
changed images from `JukesCurse/`, delete any the new ones replace, and rename
the uploads, which CurseForge titles `image-attachment_<uuid>`, back to their
file names so the gallery matches `build/JukesScreenshots/`.

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

Each addon has its own CurseForge project; its id is `## X-Curse-Project-ID:`
in `build/<Addon>/<Addon>.toc` (that line also lets the CurseForge app match
the installed folder to the project):

| Addon | Project |
| --- | --- |
| JukesTargetor | 1823357 |
| JukesGoldAudit | 1823361 |
| JukesLoot | 1823365 |
| JukesScaleCounts | 1823369 |

The token is `CURSEFORGE_API_TOKEN` in the git-ignored `.env` at the repo root.

```bash
python3 .claude/skills/curse-release/scripts/upload.py --tag vX.Y.Z --dry-run
python3 .claude/skills/curse-release/scripts/upload.py --tag vX.Y.Z [--only JukesLoot,...]
```

- Each `<Addon>-v<Version>.zip` goes to its own project as a normal file.
  Use `--only` to skip addons that didn't change (otherwise every addon gets a
  re-upload of the same version).
- `JukesAddons-all-<tag>.zip` is for GitHub only: **never upload it to CurseForge**.
- Game version: newest **WoW Forever** version on CurseForge, looked up each run.
- Release type `release`; changelog = commit subjects since the previous tag that
  touched `build/<Addon>/` (`--changelog-file` to override).
- Automatic packaging is **off** on these projects: the repo holds four addons,
  so the GitHub packager would zip all of them into each project.

Always run `--dry-run` first and show the user the changelogs and file list;
upload only after they confirm. Uploads are public and can't be undone via
the API.

Screenshots can't go through the API. Use each project's Media tab
(`https://authors.curseforge.com/#/projects/<id>/media`): upload that addon's
images from `JukesCurse/` (prefixed `targetor-`, `gold-audit-`, `loot-audit-`,
`scale-counts-`), delete any the new ones replace, and rename the uploads,
which CurseForge titles `image-attachment_<uuid>`, back to their file names.

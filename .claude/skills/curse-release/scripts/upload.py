#!/usr/bin/env python3
"""Upload the staged JukesCurse/ zips to CurseForge.

Run release.py --tag vX.Y.Z first. Each addon has its own CurseForge project,
named by `## X-Curse-Project-ID:` in build/<Addon>/<Addon>.toc. This uploads
each <Addon>-v<Version>.zip to its project, tagged with the newest WoW Forever
game version. The JukesAddons-all-*.zip is for GitHub only and is never uploaded.

Changelog: per addon, the commits since the previous tag that touched
build/<Addon>/ (or --changelog-file for all).
--only Addon[,Addon] limits the upload to some addons.
Token: CURSEFORGE_API_TOKEN from the environment or the repo's .env file.
Screenshots are not uploaded (the API has no images endpoint).
"""

import argparse
import json
import os
import re
import subprocess
import sys
import urllib.request
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
RELEASE = ROOT / "JukesCurse"
BUILD = ROOT / "build"
API = "https://wow.curseforge.com/api"
GAME_TYPE = "wow-forever"  # version-type slug; newest version of it is used


def token():
    t = os.environ.get("CURSEFORGE_API_TOKEN")
    env = ROOT / ".env"
    if not t and env.exists():
        for line in env.read_text().splitlines():
            k, _, v = line.partition("=")
            if k.strip() == "CURSEFORGE_API_TOKEN":
                t = v.strip().strip("'\"")
    if not t:
        sys.exit("CURSEFORGE_API_TOKEN not set (env or .env)")
    return t


def get(path, tok):
    req = urllib.request.Request(f"{API}{path}", headers={"X-Api-Token": tok})
    with urllib.request.urlopen(req) as r:
        return json.load(r)


def upload(tok, project, path, metadata):
    boundary = uuid.uuid4().hex
    body = b"".join([
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"metadata\"\r\n"
        f"Content-Type: application/json\r\n\r\n".encode(),
        json.dumps(metadata).encode(), b"\r\n",
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"{path.name}\"\r\n"
        f"Content-Type: application/zip\r\n\r\n".encode(),
        path.read_bytes(), b"\r\n",
        f"--{boundary}--\r\n".encode(),
    ])
    req = urllib.request.Request(
        f"{API}/projects/{project}/upload-file", data=body, method="POST",
        headers={"X-Api-Token": tok, "Content-Type": f"multipart/form-data; boundary={boundary}"})
    try:
        with urllib.request.urlopen(req) as r:
            return json.load(r)["id"]
    except urllib.error.HTTPError as e:
        sys.exit(f"upload of {path.name} failed: HTTP {e.code} {e.read().decode(errors='replace')}")


def git(*args):
    return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True).stdout.strip()


def changelog(tag, addon, version):
    prev = git("describe", "--tags", "--abbrev=0", "--exclude", tag, "HEAD")
    end = tag if git("tag", "--list", tag) else "HEAD"
    rng = f"{prev}..{end}" if prev else end
    lines = git("log", "--no-merges", "--format=- %s", rng, "--", f"build/{addon}")
    head = f"## {version}\n\nChanges since {prev}:\n\n" if prev else f"## {version}\n\n"
    return head + (lines or "- No changes to this addon"), rng


def toc_field(addon, field):
    for line in (BUILD / addon / f"{addon}.toc").read_text(encoding="utf-8").splitlines():
        m = re.match(rf"##\s*{re.escape(field)}:\s*(\S+)", line)
        if m:
            return m.group(1)
    return None


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--tag", required=True, help="release tag used for release.py, e.g. v1.6.0")
    ap.add_argument("--changelog-file", type=Path, help="markdown changelog to use instead of git log")
    ap.add_argument("--release-type", default="release", choices=["release", "beta", "alpha"])
    ap.add_argument("--only", help="comma-separated addon folders to upload, e.g. JukesLoot")
    ap.add_argument("--dry-run", action="store_true", help="show what would be uploaded, upload nothing")
    args = ap.parse_args()

    if not (RELEASE / f"JukesAddons-all-{args.tag}.zip").exists():
        sys.exit(f"JukesCurse/ not staged for {args.tag}; run release.py --tag {args.tag} first")
    zips = sorted(p for p in RELEASE.glob("*.zip") if not p.name.startswith("JukesAddons-all-"))
    only = set(args.only.split(",")) if args.only else None

    jobs = []  # (zip, addon, version, project)
    for z in zips:
        addon, _, version = z.stem.rpartition("-v")
        if only and addon not in only:
            continue
        project = toc_field(addon, "X-Curse-Project-ID")
        if not project:
            sys.exit(f"build/{addon}/{addon}.toc has no '## X-Curse-Project-ID:'")
        jobs.append((z, addon, version, int(project)))
    if not jobs:
        sys.exit("nothing to upload")

    tok = token()
    types = {t["slug"]: t for t in get("/game/version-types", tok)}
    if GAME_TYPE not in types:
        sys.exit(f"CurseForge has no version type '{GAME_TYPE}'")
    versions = [v for v in get("/game/versions", tok) if v["gameVersionTypeID"] == types[GAME_TYPE]["id"]]
    vkey = lambda v: [int(x) if x.isdigit() else 0 for x in re.split(r"\D+", v["name"])]
    game = max(versions, key=vkey)
    print(f"{types[GAME_TYPE]['name']} {game['name']} (id {game['id']}), {args.release_type}\n")

    plan = []
    for z, addon, version, project in jobs:
        if args.changelog_file:
            log, rng = args.changelog_file.read_text(encoding="utf-8"), str(args.changelog_file)
        else:
            log, rng = changelog(args.tag, addon, f"v{version}")
        name = f"{addon} v{version}"
        meta = {"changelog": log, "changelogType": "markdown", "releaseType": args.release_type,
                "gameVersions": [game["id"]], "displayName": name}
        plan.append((z, project, meta))
        print(f"{z.name}  ->  project {project}  as '{name}'  (changelog from {rng})")
        print("  " + log.replace("\n", "\n  ") + "\n")

    if args.dry_run:
        print("dry run: nothing uploaded")
        return

    for z, project, meta in plan:
        fid = upload(tok, project, z, meta)
        print(f"uploaded {z.name} -> project {project}, file id {fid}  "
              f"https://authors.curseforge.com/#/projects/{project}/files")


if __name__ == "__main__":
    main()

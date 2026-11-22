#!/usr/bin/env python3
"""Upload the staged JukesCurse/ zips to CurseForge.

Run release.py --tag vX.Y.Z first. This then uploads:

  JukesAddons-all-<tag>.zip   as the project's main file (what the CurseForge
                              app installs), tagged with the newest WoW Forever
                              game version
  <Addon>-v<Version>.zip      each as an "additional file" attached to it

Changelog: git commits since the previous tag (or --changelog-file).
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
API = "https://wow.curseforge.com/api"
PROJECT_ID = 1808490
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


def changelog(tag):
    prev = git("describe", "--tags", "--abbrev=0", "--exclude", tag, "HEAD")
    end = tag if git("tag", "--list", tag) else "HEAD"
    rng = f"{prev}..{end}" if prev else end
    lines = git("log", "--no-merges", "--format=- %s", rng)
    head = f"## {tag}\n\nChanges since {prev}:\n\n" if prev else f"## {tag}\n\n"
    return head + (lines or "- Maintenance release"), rng


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--tag", required=True, help="release tag used for release.py, e.g. v1.6.0")
    ap.add_argument("--changelog-file", type=Path, help="markdown changelog to use instead of git log")
    ap.add_argument("--release-type", default="release", choices=["release", "beta", "alpha"])
    ap.add_argument("--project", type=int, default=PROJECT_ID)
    ap.add_argument("--dry-run", action="store_true", help="show what would be uploaded, upload nothing")
    args = ap.parse_args()

    main_zip = RELEASE / f"JukesAddons-all-{args.tag}.zip"
    if not main_zip.exists():
        sys.exit(f"{main_zip.relative_to(ROOT)} missing; run release.py --tag {args.tag} first")
    singles = sorted(p for p in RELEASE.glob("*.zip") if not p.name.startswith("JukesAddons-all-"))

    tok = token()
    types = {t["slug"]: t for t in get("/game/version-types", tok)}
    if GAME_TYPE not in types:
        sys.exit(f"CurseForge has no version type '{GAME_TYPE}'")
    versions = [v for v in get("/game/versions", tok) if v["gameVersionTypeID"] == types[GAME_TYPE]["id"]]
    vkey = lambda v: [int(x) if x.isdigit() else 0 for x in re.split(r"\D+", v["name"])]
    game = max(versions, key=vkey)

    if args.changelog_file:
        log, rng = args.changelog_file.read_text(encoding="utf-8"), str(args.changelog_file)
    else:
        log, rng = changelog(args.tag)

    base = {"changelog": log, "changelogType": "markdown", "releaseType": args.release_type}
    print(f"project {args.project}, {types[GAME_TYPE]['name']} {game['name']} (id {game['id']}), "
          f"{args.release_type}, changelog from {rng}:\n")
    print("  " + log.replace("\n", "\n  ") + "\n")
    print(f"main file:        {main_zip.name}  as 'JukesAddons {args.tag}'")
    for s in singles:
        print(f"additional file:  {s.name}  as '{s.stem.replace('-v', ' v')}'")

    if args.dry_run:
        print("\ndry run: nothing uploaded")
        return

    parent = upload(tok, args.project, main_zip,
                    {**base, "displayName": f"JukesAddons {args.tag}", "gameVersions": [game["id"]]})
    print(f"\nuploaded {main_zip.name} -> file id {parent}")
    for s in singles:
        fid = upload(tok, args.project, s,
                     {**base, "displayName": s.stem.replace("-v", " v"), "parentFileID": parent})
        print(f"uploaded {s.name} -> file id {fid}")
    print(f"\nhttps://authors.curseforge.com/#/projects/{args.project}/files")


if __name__ == "__main__":
    main()

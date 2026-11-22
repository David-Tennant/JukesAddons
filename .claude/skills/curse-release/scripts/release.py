#!/usr/bin/env python3
"""Dist -> Release: stage CurseForge uploads in JukesCurse/.

Runs the build-dist step first (build/ -> dist/), then wipes JukesCurse/ and
writes everything flat into it (no subfolders):

  JukesCurse/<Addon>-v<Version>.zip     zip of dist/<Addon>/ (version from .toc)
  JukesCurse/<screenshot files>         from build/JukesScreenshots/<Addon minus "Jukes">/
  JukesCurse/JukesAddons-all-<tag>.zip  every addon in one zip (for GitHub releases)

Screenshot file names must be unique across addons (they're already prefixed,
e.g. targetor-*.jpg); a clash stops the release.

Each zip holds the <Addon>/ folder at the top level, so it extracts straight
into Interface/AddOns/.
"""

import argparse
import re
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
DIST = ROOT / "dist"
SHOTS = ROOT / "build" / "JukesScreenshots"
RELEASE = ROOT / "JukesCurse"
DIST_SCRIPT = ROOT / ".claude" / "skills" / "build-dist" / "scripts" / "dist.py"
FIXED_ZIP_TIME = (2026, 1, 1, 0, 0, 0)  # reproducible zips
IMAGE_EXT = {".jpg", ".jpeg", ".png", ".gif", ".webp"}


def toc_version(toc):
    for line in toc.read_text(encoding="utf-8").splitlines():
        m = re.match(r"##\s*Version:\s*(\S+)", line)
        if m:
            return m.group(1)
    sys.exit(f"no '## Version:' in {toc}")


def zip_dirs(zip_path, dirs):
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for d in dirs:
            z.writestr(zipfile.ZipInfo(f"{d.name}/", FIXED_ZIP_TIME), "")
            for f in sorted(p for p in d.rglob("*") if p.is_file() and p.name != ".DS_Store"):
                info = zipfile.ZipInfo(str(f.relative_to(d.parent)), FIXED_ZIP_TIME)
                info.compress_type = zipfile.ZIP_DEFLATED
                z.writestr(info, f.read_bytes())


def latest_tag():
    r = subprocess.run(["git", "describe", "--tags", "--abbrev=0"], cwd=ROOT, capture_output=True, text=True)
    return r.stdout.strip() or None


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--tag", help="name for the all-in-one zip, e.g. v1.5.0 (default: 'dev')")
    ap.add_argument("--skip-dist", action="store_true", help="reuse the existing dist/ instead of rebuilding it")
    args = ap.parse_args()
    tag = args.tag or "dev"

    if not args.skip_dist:
        subprocess.run([sys.executable, str(DIST_SCRIPT)], check=True)
        print()

    addons = sorted(d for d in DIST.iterdir() if d.is_dir() and (d / f"{d.name}.toc").exists())
    if not addons:
        sys.exit("dist/ is empty; run the build-dist step first")

    if RELEASE.exists():
        shutil.rmtree(RELEASE)
    RELEASE.mkdir()

    print("release (JukesCurse/, flat):")
    for addon in addons:
        version = toc_version(addon / f"{addon.name}.toc")
        zip_path = RELEASE / f"{addon.name}-v{version}.zip"
        zip_dirs(zip_path, [addon])
        print(f"  {zip_path.name}  ({zip_path.stat().st_size:,} bytes)")

        shot_dir = SHOTS / addon.name.removeprefix("Jukes")
        shots = sorted(p for p in shot_dir.glob("*") if p.suffix.lower() in IMAGE_EXT) if shot_dir.is_dir() else []
        if not shots:
            print(f"    (no screenshots in build/JukesScreenshots/{shot_dir.name}/)")
        for s in shots:
            dst = RELEASE / s.name
            if dst.exists():
                sys.exit(f"screenshot name clash in flat JukesCurse/: {s.name}; rename one in build/JukesScreenshots/")
            shutil.copy2(s, dst)
            print(f"    {s.name}")

    all_zip = RELEASE / f"JukesAddons-all-{tag}.zip"
    zip_dirs(all_zip, addons)
    print(f"  {all_zip.name}  ({all_zip.stat().st_size:,} bytes)")
    if not args.tag:
        print(f"\nnote: no --tag given (latest git tag is {latest_tag()}); all-in-one zip named '-dev'")


if __name__ == "__main__":
    main()

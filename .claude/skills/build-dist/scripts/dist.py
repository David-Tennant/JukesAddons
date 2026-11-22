#!/usr/bin/env python3
"""Build -> Dist: minify the Jukes addons into dist/.

Source addons live in build/<Addon>/ (any folder with a <Addon>.toc). Sources
are never modified; dist/ is wiped and rewritten:

  dist/<Addon>/...                    minified copy of each addon

Zipping for CurseForge is the release step (see the curse-release skill).

Lua files: comments and all non-essential whitespace are removed. Identifiers
are NOT renamed (WoW addons rely on globals, SavedVariables and frame names).
Every minified file is re-tokenized and must produce exactly the same token
stream as the source minus comments, otherwise the build fails.

.toc files: '## ' metadata lines and file lists are kept; '#' comment lines and
blank lines are dropped. Other files are copied unchanged.
"""

import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
SRC = ROOT / "build"
DIST = ROOT / "dist"

# ---------------------------------------------------------------- tokenizer

LONG_BRACKET = re.compile(r"\[(=*)\[")
NUMBER = re.compile(
    r"0[xX][0-9a-fA-F]*(?:\.[0-9a-fA-F]*)?(?:[pP][+-]?\d+)?"
    r"|(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?"
)
NAME = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
OPERATORS = ["...", "..", "==", "~=", "<=", ">=", "<<", ">>", "//", "::"]
WORDY = ("name", "number")


class LuaError(Exception):
    pass


def _long_close(src, i, level):
    end = src.find("]" + "=" * level + "]", i)
    if end < 0:
        raise LuaError(f"unterminated long bracket at offset {i}")
    return end + level + 2


def tokenize(src):
    """Return [(kind, text)] for Lua 5.1 source; kind 'comment' included."""
    toks, i, n = [], 0, len(src)
    if src.startswith("#"):  # shebang line
        i = src.find("\n")
        i = n if i < 0 else i
    while i < n:
        c = src[i]
        if c in " \t\r\n\f\v":
            i += 1
            continue
        if src.startswith("--", i):
            m = LONG_BRACKET.match(src, i + 2)
            if m:
                j = _long_close(src, m.end(), len(m.group(1)))
            else:
                j = src.find("\n", i)
                j = n if j < 0 else j
            toks.append(("comment", src[i:j]))
            i = j
            continue
        if c in "'\"":
            j = i + 1
            while True:
                if j >= n or src[j] == "\n":
                    raise LuaError(f"unterminated string at offset {i}")
                if src[j] == "\\":
                    j += 2
                    continue
                if src[j] == c:
                    break
                j += 1
            toks.append(("string", src[i:j + 1]))
            i = j + 1
            continue
        m = LONG_BRACKET.match(src, i)
        if m:
            j = _long_close(src, m.end(), len(m.group(1)))
            toks.append(("string", src[i:j]))
            i = j
            continue
        m = NUMBER.match(src, i)
        if m and (c.isdigit() or (c == "." and i + 1 < n and src[i + 1].isdigit())):
            toks.append(("number", m.group()))
            i = m.end()
            continue
        m = NAME.match(src, i)
        if m:
            toks.append(("name", m.group()))
            i = m.end()
            continue
        for op in OPERATORS:
            if src.startswith(op, i):
                toks.append(("op", op))
                i += len(op)
                break
        else:
            toks.append(("op", c))
            i += 1
    return toks


# ---------------------------------------------------------------- minifier

def _needs_space(a, b):
    """True if writing a then b with no gap would lex differently."""
    if a[0] in WORDY and b[0] in WORDY:
        return True
    try:
        return [t for t in tokenize(a[1] + b[1])] != [a, b]
    except LuaError:
        return True


def minify_lua(src):
    code = [t for t in tokenize(src) if t[0] != "comment"]
    out, prev = [], None
    for tok in code:
        if prev is not None and _needs_space(prev, tok):
            out.append(" ")
        out.append(tok[1])
        prev = tok
    result = "".join(out) + "\n"
    if tokenize(result) != code:  # safety net: semantics must be identical
        raise LuaError("minified output does not match source tokens")
    return result


def minify_toc(src):
    keep = []
    for line in src.splitlines():
        s = line.strip()
        if not s or (s.startswith("#") and not s.startswith("##")):
            continue
        keep.append(s)
    return "\n".join(keep) + "\n"


# ---------------------------------------------------------------- packaging

def find_addons():
    return sorted(d for d in SRC.iterdir() if d.is_dir() and (d / f"{d.name}.toc").exists())


def luac_check(path):
    luac = shutil.which("luac")
    if not luac:
        return None
    r = subprocess.run([luac, "-p", str(path)], capture_output=True, text=True)
    return r.returncode == 0, r.stderr.strip()


def main():
    if DIST.exists():
        shutil.rmtree(DIST)
    DIST.mkdir()

    addons = find_addons()
    total_in = total_out = 0
    failed = False
    print(f"{'file':45} {'source':>9} {'minified':>9}  saved")
    for addon in addons:
        for f in sorted(p for p in addon.rglob("*") if p.is_file()):
            rel = f.relative_to(SRC)
            dst = DIST / rel
            dst.parent.mkdir(parents=True, exist_ok=True)
            if f.name == ".DS_Store":
                continue
            if f.suffix == ".lua":
                src = f.read_text(encoding="utf-8")
                try:
                    dst.write_text(minify_lua(src), encoding="utf-8")
                except LuaError as e:
                    print(f"ERROR {rel}: {e}", file=sys.stderr)
                    failed = True
                    continue
                chk = luac_check(dst)
                if chk and not chk[0]:
                    # luac may be newer than Lua 5.1; report, don't fail.
                    print(f"  note: luac -p {rel}: {chk[1]}", file=sys.stderr)
            elif f.suffix == ".toc":
                dst.write_text(minify_toc(f.read_text(encoding="utf-8")), encoding="utf-8")
            else:
                shutil.copy2(f, dst)
            a, b = f.stat().st_size, dst.stat().st_size
            total_in += a
            total_out += b
            print(f"{str(rel):45} {a:>9,} {b:>9,}  {100 - 100 * b // max(a, 1):>3}%")

    if failed:
        sys.exit("dist failed")
    print(f"{'TOTAL':45} {total_in:>9,} {total_out:>9,}  {100 - 100 * total_out // max(total_in, 1):>3}%")
    print(f"\ndist: {', '.join('dist/' + a.name for a in addons)}")


if __name__ == "__main__":
    main()

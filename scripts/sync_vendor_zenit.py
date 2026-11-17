#!/usr/bin/env python3
"""Replace vendor/zenit with a pristine snapshot of one zenit commit.

ZeroWork never edits vendor/zenit by hand. Product-specific behavior lives in
src/zenit_ext/ and mounts through zenit's public extension points, so updating
zenit is: run this script, build, test, commit.

The snapshot contains exactly the files zenit ships as a Zig package (the
`.paths` allowlist of that commit's build.zig.zon), taken from Git objects
(not the working tree), so untracked or uncommitted files never leak in.

Usage:
  python3 scripts/sync_vendor_zenit.py --source /path/to/zenit --ref main
"""
import argparse
import hashlib
import io
import json
import pathlib
import re
import shutil
import subprocess
import sys
import tarfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
VENDOR = ROOT / "vendor" / "zenit"
LOCK = ROOT / "vendor" / "zenit.lock.json"


def git(source, *args, binary=False):
    out = subprocess.check_output(["git", "-C", str(source), *args])
    return out if binary else out.decode()


def package_paths(zon_text):
    start = zon_text.index(".paths")
    block = zon_text[start:zon_text.index("}", start)]
    return [p.rstrip("/") for p in re.findall(r'"([^"]+)"', block)]


def tree_digest(files):
    """files: iterable of (relative posix path, bytes) — same algorithm as verify_vendor_zenit.py."""
    digest = hashlib.sha256()
    count = 0
    for rel, data in sorted(files):
        encoded = rel.encode()
        digest.update(len(encoded).to_bytes(8, "big"))
        digest.update(encoded)
        digest.update(len(data).to_bytes(8, "big"))
        digest.update(data)
        count += 1
    return count, digest.hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, help="zenit Git checkout or worktree")
    parser.add_argument("--ref", required=True, help="branch, tag or commit to snapshot")
    args = parser.parse_args()

    source = pathlib.Path(args.source).resolve()
    commit = git(source, "rev-parse", "--verify", f"{args.ref}^{{commit}}").strip()
    zon = git(source, "show", f"{commit}:build.zig.zon")
    allow = package_paths(zon)
    tracked = git(source, "ls-tree", "-r", "--name-only", commit).splitlines()
    selected = [f for f in tracked if any(f == p or f.startswith(p + "/") for p in allow)]
    if not selected:
        sys.exit("no files selected from build.zig.zon .paths")

    archive = git(source, "archive", "--format=tar", commit, "--", *selected, binary=True)
    if VENDOR.exists():
        shutil.rmtree(VENDOR)
    VENDOR.mkdir(parents=True)
    with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
        tar.extractall(VENDOR, filter="data")

    files = [(p.relative_to(VENDOR).as_posix(), p.read_bytes()) for p in VENDOR.rglob("*") if p.is_file()]
    count, sha = tree_digest(files)
    if count != len(selected):
        sys.exit(f"snapshot file count mismatch: extracted={count} selected={len(selected)}")

    branch = args.ref if args.ref != commit else None
    lock = {
        "source": "zenit",
        "ref": branch,
        "commit": commit,
        "commit_date": git(source, "show", "-s", "--format=%cI", commit).strip(),
        "files": count,
        "sha256": sha,
        "hash_algorithm": "sorted paths relative to vendor/zenit; per file: u64be path length, path, u64be content length, content",
    }
    LOCK.write_text(json.dumps(lock, indent=2) + "\n")
    print(f"vendor/zenit <- {commit[:12]} ({branch or 'detached'}): files={count} sha256={sha}")


if __name__ == "__main__":
    main()

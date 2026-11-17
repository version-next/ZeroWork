#!/usr/bin/env python3
"""Verify vendor/zenit is exactly the pristine snapshot recorded in vendor/zenit.lock.json.

With --source <zenit checkout>, additionally confirm the recorded commit exists
there and that the snapshot equals that commit's package files byte for byte.
"""
import argparse
import hashlib
import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
VENDOR = ROOT / "vendor" / "zenit"
LOCK = ROOT / "vendor" / "zenit.lock.json"


def digest_tree(base):
    paths = subprocess.check_output(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "vendor/zenit"], cwd=ROOT, text=True
    ).splitlines()
    paths = sorted({p for p in paths if (ROOT / p).is_file()})
    digest = hashlib.sha256()
    for tracked in paths:
        path = ROOT / tracked
        relative = path.relative_to(base).as_posix().encode()
        data = path.read_bytes()
        digest.update(len(relative).to_bytes(8, "big"))
        digest.update(relative)
        digest.update(len(data).to_bytes(8, "big"))
        digest.update(data)
    return len(paths), digest.hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", help="optional zenit checkout to cross-check the locked commit")
    args = parser.parse_args()

    lock = json.loads(LOCK.read_text())
    count, actual = digest_tree(VENDOR)
    if count != lock["files"] or actual != lock["sha256"]:
        print(
            f"Zenit vendor verification failed: files={count} sha256={actual}; "
            f"lock expects files={lock['files']} sha256={lock['sha256']} (commit {lock['commit']}). "
            "vendor/zenit must not be edited by hand; re-run scripts/sync_vendor_zenit.py.",
            file=sys.stderr,
        )
        raise SystemExit(1)

    if args.source:
        import tempfile
        import shutil

        with tempfile.TemporaryDirectory() as tmp:
            script = ROOT / "scripts" / "sync_vendor_zenit.py"
            # Re-derive the snapshot into a scratch copy of the lock/vendor layout and compare hashes.
            scratch = pathlib.Path(tmp) / "repo"
            (scratch / "scripts").mkdir(parents=True)
            (scratch / "vendor").mkdir()
            shutil.copy(script, scratch / "scripts" / script.name)
            subprocess.check_call(
                [sys.executable, "-I", str(scratch / "scripts" / script.name), "--source", args.source, "--ref", lock["commit"]],
                stdout=subprocess.DEVNULL,
            )
            derived = json.loads((scratch / "vendor" / "zenit.lock.json").read_text())
            if derived["sha256"] != lock["sha256"] or derived["files"] != lock["files"]:
                print(f"Zenit vendor differs from {lock['commit']} in {args.source}", file=sys.stderr)
                raise SystemExit(1)

    ref = lock.get("ref") or "detached"
    print(f"Zenit vendor verified: {lock['commit'][:12]} ({ref}) files={count} sha256={actual}")


if __name__ == "__main__":
    main()

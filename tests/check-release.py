#!/usr/bin/env python3
"""Read-only release readiness check for exact source and recipe commits.

This command neither creates a tag nor publishes a release. The selected full
recipe commit must already have passing hosted checks, and its pinned source
must independently have a passing native check. Historical releases retain
their original qualification; this policy gates future releases.
"""

import argparse
import json
import os
from pathlib import Path
import re
import subprocess

from fork_ci import (
    ContractError, full_commit, pinned_source, release_source_provenance, successful_checks,
)


def run(command):
    result = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        raise ContractError(f"{command[0]} failed: {result.stderr.strip()}")
    return result.stdout


def run_bytes(command):
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        detail = result.stderr.decode("utf-8", errors="replace").strip()
        raise ContractError(f"{command[0]} failed: {detail}")
    return result.stdout


def check_runs(repository, commit):
    pages = json.loads(run([
        "gh", "api", f"repos/{repository}/commits/{commit}/check-runs?per_page=100&filter=all",
        "--paginate", "--slurp",
    ]))
    return [check for page in pages for check in page["check_runs"]]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY", "byebyebryan/SwayNotificationCenter"))
    parser.add_argument("--recipe-commit", required=True)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    receipt = {"repository": args.repo, "recipe_commit": args.recipe_commit,
               "status": "not-ready", "release_published": False}
    try:
        commit = full_commit(args.recipe_commit)
        if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", args.repo):
            raise ContractError("invalid repository name")
        root = Path(__file__).resolve().parent.parent
        recipe = run_bytes([
            "git", "-C", str(root), "show", f"{commit}:packaging/arch/PKGBUILD"
        ])
        source = pinned_source(recipe.decode("utf-8"))
        receipt["source_commit"] = source
        receipt["source_provenance"] = release_source_provenance(
            root, args.repo, commit, source, recipe
        )
        policy = json.loads((root / "tests/ci-policy.json").read_text())
        receipt["recipe_checks"] = successful_checks(
            check_runs(args.repo, commit), commit, policy["required_recipe_checks"])
        receipt["source_checks"] = successful_checks(
            check_runs(args.repo, source), source, policy["required_source_checks"])
        receipt["status"] = "ready"
    except (ContractError, OSError, ValueError, KeyError, TypeError) as error:
        receipt["reason"] = str(error)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(receipt, indent=2) + "\n")
    print(json.dumps(receipt, indent=2))
    return 0 if receipt["status"] == "ready" else 1


if __name__ == "__main__":
    raise SystemExit(main())

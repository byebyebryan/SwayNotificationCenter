"""Regression cases for immutable package identity and fail-closed release gates."""

import copy
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from fork_ci import (
    ContractError, full_commit, package_metadata, pinned_source,
    recipe_metadata, release_source_provenance, required_jobs, successful_checks,
)


SOURCE = "a" * 40
RECIPE = "b" * 40
CHECKSUM = "c" * 64
RECIPE_TEXT = f"_commit={SOURCE}\ncheck() {{\n meson test -C build --print-errorlogs\n}}\n"
SRCINFO = f"""pkgbase = swaync-bryan
    pkgver = 0.12.6
    pkgrel = 17
    arch = x86_64
    provides = swaync=0.12.6
    conflicts = swaync
    source = SwayNotificationCenter-{SOURCE}.tar.gz::https://github.com/byebyebryan/SwayNotificationCenter/archive/{SOURCE}.tar.gz
    sha256sums = {CHECKSUM}
pkgname = swaync-bryan
"""
PKGINFO = """pkgname = swaync-bryan
pkgver = 0.12.6-17
arch = x86_64
provides = swaync=0.12.6
conflict = swaync
"""


def check(name="native", commit=SOURCE, identifier=10, conclusion="success", **extra):
    return dict(id=identifier, name=name, head_sha=commit,
                app={"slug": "github-actions"}, status="completed", conclusion=conclusion,
                **extra)


class RecipeTests(unittest.TestCase):
    def test_canonical_recipe_and_built_package(self):
        expected = recipe_metadata(SRCINFO, RECIPE_TEXT)
        self.assertEqual(expected["source_commit"], SOURCE)
        self.assertEqual(expected["package_version"], "0.12.6-17")
        self.assertEqual(package_metadata(PKGINFO, expected)["pkgname"], ["swaync-bryan"])

    def test_moving_or_ambiguous_source_pin(self):
        for recipe in ("_commit=main", "_commit=" + SOURCE[:7], RECIPE_TEXT * 2):
            with self.subTest(recipe=recipe), self.assertRaises(ContractError):
                pinned_source(recipe)
        self.assertEqual(pinned_source(RECIPE_TEXT.replace(SOURCE, "'" + SOURCE + "'")), SOURCE)

    def test_reject_unpinned_or_foreign_archives(self):
        for old, new in ((f"archive/{SOURCE}", "archive/main"),
                         ("byebyebryan/SwayNotificationCenter", "other/fork"),
                         (CHECKSUM, "SKIP"), (CHECKSUM, CHECKSUM[:12])):
            with self.subTest(new=new), self.assertRaises(ContractError):
                recipe_metadata(SRCINFO.replace(old, new), RECIPE_TEXT)

    def test_reject_duplicate_source_or_checksum(self):
        for line in (f"source = another-archive\n", f"sha256sums = {CHECKSUM}\n"):
            with self.subTest(line=line), self.assertRaises(ContractError):
                recipe_metadata(SRCINFO + line, RECIPE_TEXT)

    def test_reject_wrong_identity_and_architecture(self):
        for old, new in (("pkgname = swaync-bryan", "pkgname = swaync-git"),
                         ("arch = x86_64", "arch = any"),
                         ("pkgrel = 17", "pkgrel = 0"),
                         ("provides = swaync=0.12.6", "provides = other"),
                         ("conflicts = swaync", "conflicts = other")):
            with self.subTest(new=new), self.assertRaises(ContractError):
                recipe_metadata(SRCINFO.replace(old, new), RECIPE_TEXT)
        with self.assertRaises(ContractError):
            recipe_metadata(SRCINFO + "epoch = 1\n", RECIPE_TEXT)

    def test_checks_cannot_be_removed_from_the_recipe(self):
        with self.assertRaises(ContractError):
            recipe_metadata(SRCINFO, f"_commit={SOURCE}\n")

    def test_built_package_must_match_the_recipe(self):
        expected = recipe_metadata(SRCINFO, RECIPE_TEXT)
        for old, new in (("pkgname = swaync-bryan", "pkgname = swaync-bryan-debug"),
                         ("pkgver = 0.12.6-17", "pkgver = 0.12.6-16"),
                         ("arch = x86_64", "arch = aarch64"),
                         ("provides = swaync=0.12.6", "provides = other"),
                         ("conflict = swaync", "conflict = other")):
            with self.subTest(new=new), self.assertRaises(ContractError):
                package_metadata(PKGINFO.replace(old, new), expected)


class HostedChecksTests(unittest.TestCase):
    def test_accept_completed_exact_commit_checks(self):
        checks = [check(), check("Fork required checks", RECIPE)]
        result = successful_checks(checks, SOURCE, ["native"])
        self.assertEqual(result["native"]["id"], 10)

    def test_source_result_does_not_qualify_the_recipe(self):
        with self.assertRaises(ContractError):
            successful_checks([check()], RECIPE, ["native"])

    def test_other_apps_cannot_satisfy_the_gate(self):
        value = check()
        value["app"]["slug"] = "other-app"
        with self.assertRaises(ContractError):
            successful_checks([value], SOURCE, ["native"])

    def test_newer_failure_overrides_old_success(self):
        for conclusion in ("failure", "cancelled", "skipped", "neutral", "timed_out", None):
            with self.subTest(conclusion=conclusion), self.assertRaises(ContractError):
                successful_checks([check(), check(identifier=11, conclusion=conclusion)],
                                  SOURCE, ["native"])

    def test_newer_success_can_qualify_a_rerun(self):
        result = successful_checks([check(conclusion="failure"), check(identifier=11)],
                                   SOURCE, ["native"])
        self.assertEqual(result["native"]["id"], 11)

    def test_in_progress_success_is_not_completed_evidence(self):
        value = check()
        value["status"] = "in_progress"
        with self.assertRaises(ContractError):
            successful_checks([value], SOURCE, ["native"])

    def test_missing_required_check_and_empty_policy_fail(self):
        for names in (["native", "arch-recipe"], [], ["native", "native"]):
            with self.subTest(names=names), self.assertRaises(ContractError):
                successful_checks([check()], SOURCE, names)

    def test_short_and_moving_commits_are_rejected(self):
        for value in ("main", "HEAD", SOURCE[:7], SOURCE.upper(), SOURCE + ":file"):
            with self.subTest(value=value), self.assertRaises(ContractError):
                full_commit(value)


class RequiredGateTests(unittest.TestCase):
    def setUp(self):
        self.needs = {name: {"result": "success"} for name in ("native", "arch-recipe", "policy")}

    def test_all_prerequisites_must_succeed(self):
        required_jobs(self.needs)
        for name in self.needs:
            for result in ("failure", "cancelled", "skipped", None):
                value = copy.deepcopy(self.needs)
                value[name]["result"] = result
                with self.subTest(name=name, result=result), self.assertRaises(ContractError):
                    required_jobs(value)

    def test_missing_or_renamed_job_fails(self):
        for value in ({}, {"native": {"result": "success"}},
                      {**self.needs, "unexpected": {"result": "success"}}):
            with self.subTest(value=value), self.assertRaises(ContractError):
                required_jobs(value)

    def test_gate_entrypoint_reports_failure_for_skipped_job(self):
        path = Path(__file__).with_name("check-ci-gate.py")
        for result, status in (("success", 0), ("skipped", 1)):
            needs = copy.deepcopy(self.needs)
            needs["arch-recipe"]["result"] = result
            run = subprocess.run([sys.executable, str(path)], text=True, capture_output=True,
                                 env=dict(os.environ, FORK_CHECK_NEEDS=json.dumps(needs)))
            self.assertEqual(run.returncode, status, run.stderr)

    def test_protection_and_release_policy_select_the_same_recipe_checks(self):
        policy = json.loads(Path(__file__).with_name("ci-policy.json").read_text())
        self.assertEqual(policy["maintained_branch"], "niri-plus")
        self.assertEqual(policy["required_recipe_checks"],
                         policy["branch_protection"]["required_status_checks"]["contexts"])

    def test_fork_workflows_only_trigger_downstream_checks_on_niri_plus(self):
        root = Path(__file__).resolve().parent.parent
        for workflow_name in ("fork-checks", "ubuntu-build", "linting", "fedora-build"):
            text = (root / ".github/workflows" / f"{workflow_name}.yml").read_text()
            for event in ("push", "pull_request"):
                match = re.search(
                    rf"(?ms)^  {event}:\n(.*?)(?=^  [A-Za-z0-9_-]+:|\Z)", text
                )
                self.assertIsNotNone(match, f"{workflow_name} lacks a {event} trigger")
                branches = re.search(r"branches:\s*\[([^\]]*)\]", match.group(1))
                self.assertIsNotNone(branches, f"{workflow_name} {event} has no inline branches")
                self.assertEqual(
                    {name.strip() for name in branches.group(1).split(",")},
                    {"niri-plus"},
                )
            self.assertRegex(text, r"(?m)^  workflow_dispatch:\s*$")

    def test_fedora_source_build_remains_opt_in_for_the_fork(self):
        root = Path(__file__).resolve().parent.parent
        text = (root / ".github/workflows/fedora-build.yml").read_text()
        self.assertIn("github.repository == 'ErikReider/SwayNotificationCenter'", text)
        self.assertIn("github.repository == 'byebyebryan/SwayNotificationCenter'", text)
        self.assertIn("vars.SWAYNC_ENABLE_FEDORA_CHECKS == 'true'", text)
        for workflow_name in ("fedora-copr", "PKGBUILD-build"):
            publisher = (root / ".github/workflows" / f"{workflow_name}.yml").read_text()
            self.assertIn(
                "if: github.repository == 'ErikReider/SwayNotificationCenter'", publisher
            )

    def test_release_entrypoint_rejects_a_moving_ref_without_querying_github(self):
        run = subprocess.run([sys.executable, str(Path(__file__).with_name("check-release.py")),
                              "--recipe-commit", "main"], text=True, capture_output=True)
        self.assertEqual(run.returncode, 1)
        self.assertEqual(json.loads(run.stdout)["status"], "not-ready")


class ReleaseEntrypointTests(unittest.TestCase):
    def invoke(self, source_success=True, recipe_failure=False):
        path = Path(__file__).with_name("check-release.py")
        spec = importlib.util.spec_from_file_location("release_check", path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        policy = json.loads(path.with_name("ci-policy.json").read_text())

        def fixture_command(command):
            if command[0] != "gh":
                raise AssertionError(command)
            if f"/commits/{RECIPE}/" in command[2]:
                values = [check(name, RECIPE, identifier=i + 1)
                          for i, name in enumerate(policy["required_recipe_checks"])]
                if recipe_failure:
                    values.append(check("Fork required checks", RECIPE, identifier=100,
                                        conclusion="failure"))
            else:
                self.assertIn(f"/commits/{SOURCE}/", command[2])
                values = [check()] if source_success else []
            return json.dumps([{"check_runs": values}])

        def fixture_git_bytes(command):
            self.assertEqual(command[0], "git")
            return RECIPE_TEXT.encode("utf-8")

        def fixture_provenance(root, recipe_commit, source_commit):
            self.assertEqual(recipe_commit, RECIPE)
            self.assertEqual(source_commit, SOURCE)
            return "source-ancestor"

        output = io.StringIO()
        with patch.object(module, "run", fixture_command), \
                patch.object(module, "run_bytes", fixture_git_bytes), \
                patch.object(module, "release_source_provenance", fixture_provenance), \
                patch.object(sys, "argv", [str(path), "--recipe-commit", RECIPE]), \
                contextlib.redirect_stdout(output):
            status = module.main()
        return status, json.loads(output.getvalue())

    def test_readiness_requires_both_exact_commits_and_never_publishes(self):
        status, result = self.invoke()
        self.assertEqual(status, 0)
        self.assertEqual(result["source_commit"], SOURCE)
        self.assertEqual(result["recipe_commit"], RECIPE)
        self.assertEqual(result["source_provenance"], "source-ancestor")
        self.assertEqual(result["status"], "ready")
        self.assertFalse(result["release_published"])

    def test_missing_source_native_check_keeps_release_not_ready(self):
        status, result = self.invoke(source_success=False)
        self.assertEqual(status, 1)
        self.assertEqual(result["status"], "not-ready")
        self.assertIn("native: missing", result["reason"])

    def test_recipe_check_failure_keeps_release_not_ready(self):
        status, result = self.invoke(recipe_failure=True)
        self.assertEqual(status, 1)
        self.assertIn("Fork required checks", result["reason"])


class TemporaryGitHistory:
    """A small real Git graph for checking strict source/recipe ancestry."""

    def __init__(self, root):
        self.root = root
        self.git("init", "--quiet", "--initial-branch=source")
        self.git("config", "user.name", "Fork CI Test")
        self.git("config", "user.email", "fork-ci-test@example.invalid")

        (root / "source.txt").write_text("source commit\n")
        self.git("add", "source.txt")
        self.git("commit", "--quiet", "-m", "source")
        self.source_commit = self.git("rev-parse", "HEAD")

        self.write_recipe(self.recipe(self.source_commit, CHECKSUM))
        self.git("add", "packaging/arch/PKGBUILD")
        self.git("commit", "--quiet", "-m", "recipe pins source")
        self.recipe_commit = self.git("rev-parse", "HEAD")

        empty_tree = self.git("mktree", input_bytes=b"")
        self.unrelated_source_commit = self.git("commit-tree", empty_tree, "-m", "unrelated source")

    def git(self, *arguments, input_bytes=None):
        result = subprocess.run(
            ["git", "-C", str(self.root), *arguments], input=input_bytes,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
        if result.returncode:
            raise AssertionError(result.stderr.decode("utf-8", errors="replace"))
        return result.stdout.decode("utf-8").strip()

    @staticmethod
    def recipe(source, checksum):
        return (
            "pkgname=swaync-bryan\n"
            "pkgver=0.12.6\n"
            "pkgrel=17\n"
            f"_commit={source}\n"
            f"sha256sums=('{checksum}')\n"
        ).encode("utf-8")

    def write_recipe(self, content):
        path = self.root / "packaging/arch/PKGBUILD"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)

class ReleaseProvenanceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="fork-ci-provenance-")
        self.history = TemporaryGitHistory(Path(self.temporary.name))

    def tearDown(self):
        self.temporary.cleanup()

    def test_source_ancestor_of_recipe_is_accepted(self):
        result = release_source_provenance(
            self.history.root, self.history.recipe_commit, self.history.source_commit,
        )
        self.assertEqual(result, "source-ancestor")

    def test_non_ancestor_source_is_rejected(self):
        with self.assertRaisesRegex(ContractError, "not an ancestor"):
            release_source_provenance(
                self.history.root, self.history.recipe_commit,
                self.history.unrelated_source_commit,
            )

    def test_missing_source_object_fails_closed(self):
        with self.assertRaises(ContractError):
            release_source_provenance(
                self.history.root, self.history.recipe_commit, "f" * 40,
            )

    def test_missing_recipe_object_fails_closed(self):
        with self.assertRaises(ContractError):
            release_source_provenance(
                self.history.root, "e" * 40, self.history.source_commit,
            )


if __name__ == "__main__":
    unittest.main()

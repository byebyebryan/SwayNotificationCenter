"""Small, shared validation contracts for the fork's package and release checks."""

import re
import subprocess


HISTORICAL_RELEASE_17_REPOSITORY = "byebyebryan/SwayNotificationCenter"
HISTORICAL_RELEASE_17_RECIPE_COMMIT = "c6eeafb4ded51afc0a5f9a3d092fb1d4a86d0662"
HISTORICAL_RELEASE_17_SOURCE_COMMIT = "3d4458262c23ac66820cbb7a63b171bab1053ae8"
HISTORICAL_RELEASE_17_SOURCE_SHA256 = "11d591899424a1cdc6a627c53f2b2aab3a91e56fa1ff390ba0d4878806e832e6"
HISTORICAL_RELEASE_17_MIGRATION_BASE = "ccbcdd97c3e9ce342d78e065f99a64f3ac87cc42"
CANONICAL_ARCH_RECIPE_PATH = "packaging/arch/PKGBUILD"


class ContractError(ValueError):
    """The selected recipe or CI evidence does not qualify a release."""


def _git_output(root, *arguments):
    try:
        result = subprocess.run(
            ["git", "-C", str(root), *arguments],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
    except OSError as error:
        raise ContractError(f"git evidence is unavailable: {error}") from error
    if result.returncode:
        detail = result.stderr.decode("utf-8", errors="replace").strip()
        raise ContractError(f"git {' '.join(arguments)} failed: {detail}")
    return result.stdout


def git_is_ancestor(root, ancestor, descendant):
    """Return ancestry evidence, failing closed when either commit is unavailable."""
    full_commit(ancestor)
    full_commit(descendant)
    try:
        result = subprocess.run(
            ["git", "-C", str(root), "merge-base", "--is-ancestor", ancestor, descendant],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
    except OSError as error:
        raise ContractError(f"git ancestry evidence is unavailable: {error}") from error
    if result.returncode == 0:
        return True
    if result.returncode == 1:
        return False
    detail = result.stderr.decode("utf-8", errors="replace").strip()
    raise ContractError(f"git ancestry evidence is unavailable: {detail}")


def _historical_release_17_tuple(recipe):
    try:
        text = recipe.decode("utf-8")
    except UnicodeDecodeError as error:
        raise ContractError("historical release-17 recipe is not UTF-8") from error
    source = pinned_source(text)
    checksums = re.findall(rb"^sha256sums=\(['\"]([0-9a-f]{64})['\"]\)\s*$", recipe, re.M)
    if len(checksums) != 1:
        raise ContractError("historical release-17 recipe must declare one literal SHA-256")
    return source, checksums[0].decode("ascii")


def release_source_provenance(root, repository, recipe_commit, source_commit, recipe):
    """Require normal ancestry, or the exact release-17 pin on the migrated lineage."""
    full_commit(recipe_commit)
    full_commit(source_commit)
    if git_is_ancestor(root, source_commit, recipe_commit):
        return "source-ancestor"

    if repository != HISTORICAL_RELEASE_17_REPOSITORY:
        raise ContractError("historical release-17 compatibility is limited to the fork repository")
    if source_commit != HISTORICAL_RELEASE_17_SOURCE_COMMIT:
        raise ContractError("non-ancestor source is not the preserved release-17 source")
    if recipe_commit == HISTORICAL_RELEASE_17_MIGRATION_BASE or not git_is_ancestor(
        root, HISTORICAL_RELEASE_17_MIGRATION_BASE, recipe_commit
    ):
        raise ContractError(
            "release-17 compatibility requires a recipe commit after the consolidated preview"
        )

    historical_recipe = _git_output(
        root, "show", f"{HISTORICAL_RELEASE_17_RECIPE_COMMIT}:{CANONICAL_ARCH_RECIPE_PATH}"
    )
    if recipe != historical_recipe:
        raise ContractError("non-ancestor recipe differs from the immutable release-17 canonical recipe")
    if _historical_release_17_tuple(historical_recipe) != (
        HISTORICAL_RELEASE_17_SOURCE_COMMIT, HISTORICAL_RELEASE_17_SOURCE_SHA256
    ):
        raise ContractError("immutable release-17 recipe does not contain the pinned source/checksum tuple")
    if not git_is_ancestor(
        root, HISTORICAL_RELEASE_17_SOURCE_COMMIT, HISTORICAL_RELEASE_17_RECIPE_COMMIT
    ):
        raise ContractError("preserved release-17 source is not an ancestor of its historical recipe")
    return "historical-release-17"


def full_commit(value):
    if not re.fullmatch(r"[0-9a-f]{40}", value):
        raise ContractError("a full lowercase 40-character commit SHA is required")
    return value


def fields(text):
    result = {}
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#") or " = " not in line:
            continue
        key, value = line.split(" = ", 1)
        result.setdefault(key, []).append(value)
    return result


def one(values, name):
    found = values.get(name, [])
    if len(found) != 1:
        raise ContractError(f"expected exactly one {name}")
    return found[0]


def pinned_source(recipe):
    matches = re.findall(r"^_commit=([\"']?)([0-9a-f]{40})\1\s*$", recipe, re.M)
    if len(matches) != 1:
        raise ContractError("recipe must declare one literal full _commit")
    return full_commit(matches[0][1])


def recipe_metadata(srcinfo, recipe):
    data = fields(srcinfo)
    if one(data, "pkgbase") != "swaync-bryan" or one(data, "pkgname") != "swaync-bryan":
        raise ContractError("expected the canonical swaync-bryan recipe")
    version, release = one(data, "pkgver"), one(data, "pkgrel")
    if not re.fullmatch(r"[0-9]+(?:\.[0-9]+)+", version):
        raise ContractError("unexpected upstream package version")
    if not re.fullmatch(r"[1-9][0-9]*", release):
        raise ContractError("unexpected downstream package release")
    if data.get("arch") != ["x86_64"]:
        raise ContractError("this check qualifies the x86_64 package only")
    commit = pinned_source(recipe)
    source = one(data, "source")
    expected = (
        f"SwayNotificationCenter-{commit}.tar.gz::"
        f"https://github.com/byebyebryan/SwayNotificationCenter/archive/{commit}.tar.gz"
    )
    if source != expected:
        raise ContractError("source must be the canonical immutable fork archive")
    checksum = one(data, "sha256sums")
    if not re.fullmatch(r"[0-9a-f]{64}", checksum):
        raise ContractError("source must have a real SHA-256 checksum, never SKIP")
    if "epoch" in data:
        raise ContractError("a package epoch needs an explicit contract update")
    if f"swaync={version}" not in data.get("provides", []) or "swaync" not in data.get("conflicts", []):
        raise ContractError("recipe must provide swaync and declare its package conflict")
    if not re.search(r"^check\s*\(\s*\)\s*\{", recipe, re.M):
        raise ContractError("recipe must retain its check() function")
    return {
        "package_name": "swaync-bryan",
        "package_version": f"{version}-{release}",
        "upstream_version": version,
        "architecture": "x86_64",
        "source_commit": commit,
        "source_filename": f"SwayNotificationCenter-{commit}.tar.gz",
        "source_url": source.split("::", 1)[1],
        "source_sha256": checksum,
    }


def package_metadata(text, expected):
    data = fields(text)
    for key, value in (("pkgname", expected["package_name"]),
                       ("pkgver", expected["package_version"]),
                       ("arch", expected["architecture"])):
        if one(data, key) != value:
            raise ContractError(f"built package has the wrong {key}")
    if f"swaync={expected['upstream_version']}" not in data.get("provides", []):
        raise ContractError("built package does not provide the selected swaync version")
    if "swaync" not in data.get("conflict", []):
        raise ContractError("built package lost its swaync conflict")
    return data


def successful_checks(checks, commit, required):
    """Use the newest exact-commit GitHub Actions result for every required name."""
    full_commit(commit)
    if not required or len(set(required)) != len(required):
        raise ContractError("required check names must be nonempty and unique")
    latest = {}
    for check in checks:
        if check.get("head_sha") != commit or check.get("app", {}).get("slug") != "github-actions":
            continue
        name = check.get("name")
        if name in required and check.get("id", 0) > latest.get(name, {}).get("id", -1):
            latest[name] = check
    failures = []
    for name in required:
        check = latest.get(name)
        if not check:
            failures.append(f"{name}: missing")
        elif check.get("status") != "completed" or check.get("conclusion") != "success":
            failures.append(f"{name}: {check.get('status')}/{check.get('conclusion')}")
    if failures:
        raise ContractError("required checks are not successful: " + "; ".join(failures))
    return {name: {key: latest[name].get(key) for key in ("id", "conclusion", "html_url")}
            for name in required}


def required_jobs(needs):
    expected = {"native", "arch-recipe", "policy"}
    if set(needs) != expected:
        raise ContractError("required gate must receive native, arch-recipe and policy results")
    failures = [f"{name}: {value.get('result')}" for name, value in needs.items()
                if value.get("result") != "success"]
    if failures:
        raise ContractError("fork checks did not all pass: " + "; ".join(failures))

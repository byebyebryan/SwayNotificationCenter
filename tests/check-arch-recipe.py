#!/usr/bin/env python3
"""Build the canonical checksum-pinned Arch recipe, without installing its package.

Run as an ordinary user in a disposable Arch container with the recipe's build
and runtime dependencies already installed. Only PKGBUILD enters the clean
build directory; the application source must come from its pinned archive.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile

from fork_ci import ContractError, fields, one, package_metadata, recipe_metadata


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    source = Path(__file__).resolve().parent.parent
    parser.add_argument("--recipe", type=Path, default=source / "packaging/arch/PKGBUILD")
    parser.add_argument("--artifacts", type=Path, default=source / "build/fork-package-artifacts")
    args = parser.parse_args()
    if os.geteuid() == 0:
        parser.error("run makepkg as an ordinary user in a disposable Arch environment")
    for program in ("makepkg", "bsdtar"):
        if shutil.which(program) is None:
            parser.error(f"missing check tool: {program}")
    artifacts = args.artifacts.resolve()
    artifacts.mkdir(parents=True, exist_ok=True)
    receipt_path = artifacts / "receipt.json"
    receipt_path.unlink(missing_ok=True)
    recipe = args.recipe.resolve().read_bytes()
    log = artifacts / "build.log"
    log.write_text("")
    with tempfile.TemporaryDirectory(prefix="swaync-arch-recipe-") as temporary:
        build = Path(temporary)
        (build / "PKGBUILD").write_bytes(recipe)
        env = dict(os.environ)
        for variable in ("PKGDEST", "SRCDEST", "BUILDDIR", "SRCPKGDEST", "LOGDEST"):
            env[variable] = str(build)

        def run(command):
            description = shlex.join(map(str, command))
            print("Running " + description, flush=True)
            result = subprocess.run(list(map(str, command)), cwd=build, env=env,
                                    text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            with log.open("a") as output:
                output.write("Running " + description + "\n" + result.stdout)
            print(result.stdout, end="", flush=True)
            result.check_returncode()
            return result.stdout

        srcinfo = run(["makepkg", "--printsrcinfo"])
        expected = recipe_metadata(srcinfo, recipe.decode())
        (artifacts / "PKGBUILD").write_bytes(recipe)
        (artifacts / "source-info.txt").write_text(srcinfo)
        run(["makepkg", "--verifysource", "--noconfirm"])
        archive = build / expected["source_filename"]
        if not archive.is_file() or digest(archive) != expected["source_sha256"]:
            raise ContractError("downloaded source archive does not match its pin")
        # --clean deletes phase logs before we can qualify check(). The owned
        # TemporaryDirectory removes all build state after evidence is copied.
        run(["makepkg", "--cleanbuild", "--noconfirm", "--log"])
        check_logs = list(build.glob("*-check.log*"))
        if not check_logs:
            raise ContractError("makepkg did not record execution of recipe check()")
        for path in check_logs:
            shutil.copy2(path, artifacts / path.name)
        packages = []
        for line in run(["makepkg", "--packagelist"]).splitlines():
            package = Path(line).resolve()
            if not package.is_relative_to(build) or not package.is_file():
                raise ContractError("package output escaped the clean build directory or is missing")
            metadata = run(["bsdtar", "-xOf", package, ".PKGINFO"])
            # makepkg may also emit a split debug package. Qualify the runtime package.
            if one(fields(metadata), "pkgname") != expected["package_name"]:
                continue
            package_metadata(metadata, expected)
            shutil.copy2(package, artifacts / package.name)
            (artifacts / "PKGINFO").write_text(metadata)
            (artifacts / "BUILDINFO").write_text(run(["bsdtar", "-xOf", package, ".BUILDINFO"]))
            packages.append({"filename": package.name, "sha256": digest(package)})
        if len(packages) != 1:
            raise ContractError("expected one canonical runtime package")
        receipt = dict(expected, recipe_sha256=hashlib.sha256(recipe).hexdigest(),
                       packages=packages, check_function_executed=True,
                       checkout_source_used=False, package_installed=False,
                       status="passed")
        receipt_path.write_text(json.dumps(receipt, indent=2) + "\n")
        print(json.dumps(receipt, indent=2), flush=True)


if __name__ == "__main__":
    try:
        main()
    except (ContractError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error)) from error

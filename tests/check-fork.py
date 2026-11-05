#!/usr/bin/env python3
"""Build and check the fork using private native fixtures, without installation."""

import argparse
from pathlib import Path
import shlex
import shutil
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-dir", type=Path, default=Path("build"))
    parser.add_argument("--artifacts", type=Path,
                        help="native captures and check log (defaults inside the build)")
    parser.add_argument("--compositor", action="store_true",
                        help="also test notifier/actions on private Niri and owned Kitty clients")
    args = parser.parse_args()
    source = Path(__file__).resolve().parent.parent
    build = args.build_dir.resolve()
    artifacts = (args.artifacts.resolve() if args.artifacts else
                 build / "fork-check-artifacts")
    required = ["meson", "ninja", "dbus-run-session", "xvfb-run", "Xvfb", "xauth"]
    if args.compositor:
        required += ["niri", "kitty"]
    missing = [tool for tool in required if shutil.which(tool) is None]
    if missing:
        parser.error("missing check tools: " + ", ".join(missing))

    check_log = None

    def run(command):
        description = "Running " + shlex.join(map(str, command))
        print(description, flush=True)
        result = subprocess.run(list(map(str, command)), cwd=source, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        print(result.stdout, end="", flush=True)
        if check_log is not None:
            with check_log.open("a") as output:
                output.write(description + "\n" + result.stdout)
        result.check_returncode()

    if not (build / "meson-private/coredata.dat").is_file():
        run(["meson", "setup", build, source, "--buildtype=debugoptimized"])
    artifacts.mkdir(parents=True, exist_ok=True)
    check_log = artifacts / "checks.log"
    check_log.write_text("")
    run(["meson", "compile", "-C", build])
    run(["meson", "compile", "-C", build, "widget-interaction-test"])
    run(["meson", "test", "-C", build, "--print-errorlogs"])
    run([sys.executable, source / "tests/widget-interactions.py", "--binary",
         build / "widget-interaction-test", "--screenshot", artifacts / "information.png"])
    if args.compositor:
        common = [sys.executable, source / "tests/notification-actions.py",
                  "--binary", build / "src/swaync"]
        run([*common, "--information", "--dashboard-screenshot",
             artifacts / "information-control-center.png"])
        run([*common, "--dashboard-screenshot", artifacts / "legacy-control-center.png"])
    # Preserve the test summaries and compiler output without copying build trees.
    logs = build / "meson-logs"
    for name in ("testlog.txt", "testlog.json", "meson-log.txt"):
        if (logs / name).is_file():
            shutil.copy2(logs / name, artifacts / name)
    print("Fork native checks passed. Artifacts: " + str(artifacts), flush=True)


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.returncode) from error

#!/usr/bin/env python3
"""Run native widget regressions on a private Xvfb display and D-Bus session."""
import argparse
import os
from pathlib import Path
import signal
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--binary", required=True)
parser.add_argument("--stylesheet",
                    help="compiled GTK stylesheet (defaults to the binary's Meson build tree)")
parser.add_argument("--screenshot", help="write the deterministic Information fixture PNG")
args = parser.parse_args()
binary = Path(args.binary).resolve()
stylesheet = (Path(args.stylesheet).resolve() if args.stylesheet else
              binary.parent / "data" / "style" / "style.css")
if not stylesheet.is_file():
    parser.error(f"compiled stylesheet not found: {stylesheet}")
with tempfile.TemporaryDirectory(prefix="swaync-widget-tests-") as directory:
    root = Path(directory)
    runtime = root / "runtime"
    runtime.mkdir(mode=0o700)
    bus = root / "bus.conf"
    bus.write_text('<busconfig><type>session</type><listen>unix:tmpdir=/tmp</listen>'
                   '<auth>EXTERNAL</auth><policy context="default"><allow own="*"/>'
                   '<allow send_destination="*" eavesdrop="true"/>'
                   '<allow eavesdrop="true"/></policy></busconfig>')
    env = {**os.environ, "SWAYNC_PRIVATE_WIDGET_TEST": "1", "GDK_BACKEND": "x11",
           "GSK_RENDERER": "cairo", "LIBGL_ALWAYS_SOFTWARE": "1", "GTK_A11Y": "test",
           "GIO_USE_VFS": "local", "GSETTINGS_BACKEND": "memory", "LC_ALL": "C.UTF-8",
           "GSETTINGS_SCHEMA_DIR": str(binary.parent / "data"),
           "XDG_CONFIG_HOME": str(root / "config"), "XDG_STATE_HOME": str(root / "state"),
           "XDG_CACHE_HOME": str(root / "cache"), "XDG_RUNTIME_DIR": str(runtime),
           "DBUS_SYSTEM_BUS_ADDRESS": "unix:path=" + str(root / "no-system-bus"),
           "PULSE_SERVER": "unix:" + str(root / "no-audio-server"),
           "SWAYNC_PRIVATE_WIDGET_CSS": str(stylesheet)}
    if args.screenshot:
        env["SWAYNC_PRIVATE_WIDGET_SCREENSHOT"] = str(Path(args.screenshot).resolve())
    process = subprocess.Popen(["dbus-run-session", "--config-file", str(bus), "--",
                                "xvfb-run", "-a", str(binary)], env=env, start_new_session=True)
    try:
        raise SystemExit(process.wait(timeout=30))
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGTERM)
        process.wait(timeout=5)
        raise

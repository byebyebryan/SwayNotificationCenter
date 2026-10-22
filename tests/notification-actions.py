#!/usr/bin/env python3
"""Exercise real GTK notification history and D-Bus actions on a private bus.

Requires Niri, Xvfb and Python GObject introspection. Does not touch the desktop bus,
running notification service, or compositor. Pass the freshly built binary.
"""

import argparse
import json
import os
from pathlib import Path
import select
import subprocess
import sys
import tempfile
import time


def run(binary, client_test):
    import gi
    gi.require_version("Gio", "2.0")
    from gi.repository import Gio, GLib

    assert os.environ.get("SWAYNC_PRIVATE_ACTION_TEST") == "1"
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    context = GLib.MainContext.default()
    events = []
    subscription = bus.signal_subscribe(
        None, "org.freedesktop.Notifications", None, "/org/freedesktop/Notifications", None,
        Gio.DBusSignalFlags.NONE,
        lambda _c, _s, _p, _i, member, parameters: events.append((member, parameters.unpack())),
    )

    def pump(seconds=0.1):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            while context.pending():
                context.iteration(False)
            time.sleep(0.005)

    def call(member, signature, args, *, cc=True):
        return bus.call_sync(
            "org.erikreider.swaync.cc" if cc else "org.freedesktop.Notifications",
            "/org/erikreider/swaync/cc" if cc else "/org/freedesktop/Notifications",
            "org.erikreider.swaync.cc" if cc else "org.freedesktop.Notifications",
            member, GLib.Variant(signature, args), None, Gio.DBusCallFlags.NO_AUTO_START, 2000, None,
        ).unpack()

    def notify(title, *, replace=0, actions=None, hints=None, timeout=100):
        return call("Notify", "(susssasa{sv}i)",
                    ("action-test", replace, "", title, "body " + title,
                     ["default", "Open"] if actions is None else actions, hints or {}, timeout), cc=False)[0]

    def snapshot(nid):
        return call("GetNotification", "(u)", (nid,))[0]

    def invoke(nid, revision, action="default"):
        return call("InvokeAction", "(uss)", (nid, revision, action))[0]

    def activated():
        pump()
        return [args for member, args in events if member == "ActionInvoked"]

    with tempfile.TemporaryDirectory(prefix="swaync-actions-") as directory:
        root = Path(directory)
        config = root / "config.json"
        config.write_text(json.dumps({"layer-shell": True, "widgets": ["notifications"],
                                      "timeout": 1, "timeout-low": 1, "transition-time": 0,
                                      "notification-grouping": True}))
        style = root / "style.css"
        style.write_text("* {}\n")
        read_fd, write_fd = os.pipe()
        xvfb = subprocess.Popen(["Xvfb", "-displayfd", str(write_fd), "-screen", "0", "800x600x24", "-nolisten", "tcp"],
                                pass_fds=(write_fd,), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        os.close(write_fd)
        server = None
        compositor = None
        compositor_log = None
        try:
            assert select.select([read_fd], [], [], 5)[0], "Xvfb did not start"
            display = os.read(read_fd, 100).decode().strip()
            runtime = root / "runtime"
            runtime.mkdir(mode=0o700)
            env = {**os.environ, "DISPLAY": ":" + display, "GSK_RENDERER": "cairo", "LIBGL_ALWAYS_SOFTWARE": "1",
                   "GTK_A11Y": "none", "XDG_CONFIG_HOME": str(root / "config"),
                   "XDG_CACHE_HOME": str(root / "cache"), "XDG_STATE_HOME": str(root / "state"),
                   "XDG_RUNTIME_DIR": str(runtime), "GIO_USE_VFS": "local", "GSETTINGS_BACKEND": "memory"}
            env.pop("WAYLAND_DISPLAY", None)
            env.pop("NIRI_SOCKET", None)
            niri_config = root / "niri.kdl"
            niri_config.write_text("")
            compositor_log = (root / "niri.log").open("w+")
            compositor = subprocess.Popen(["niri", "-c", str(niri_config)], env=env,
                                          stdout=compositor_log, stderr=subprocess.STDOUT)
            deadline = time.monotonic() + 8
            while not list(runtime.glob("wayland-*[!k]")):
                if compositor.poll() is not None or time.monotonic() >= deadline:
                    compositor_log.flush(); compositor_log.seek(0)
                    raise AssertionError(compositor_log.read())
                time.sleep(0.05)
            sockets = [p for p in runtime.glob("wayland-*") if not p.name.endswith(".lock")]
            env["WAYLAND_DISPLAY"] = sockets[0].name
            env["GDK_BACKEND"] = "wayland"
            ipc_sockets = list(runtime.glob("niri*.sock"))
            assert len(ipc_sockets) == 1
            env["NIRI_SOCKET"] = str(ipc_sockets[0])
            with (root / "server.log").open("w+") as log:
                def start():
                    process = subprocess.Popen([binary, "-c", str(config), "-s", str(style)], env=env,
                                               stdout=log, stderr=subprocess.STDOUT)
                    deadline = time.monotonic() + 8
                    while time.monotonic() < deadline:
                        try:
                            call("GetNotification", "(u)", (0,))
                            return process
                        except GLib.Error:
                            if process.poll() is not None:
                                log.flush(); log.seek(0)
                                raise AssertionError(log.read())
                            pump(0.05)
                    process.terminate(); process.wait(timeout=3)
                    raise AssertionError("SwayNC did not acquire private bus")

                server = start()
                a = notify("older")
                a_revision = snapshot(a)["revision"]
                pump(0.3)
                assert snapshot(a)["revision"] == a_revision
                assert not any(member == "NotificationClosed" and args[0] == a for member, args in events)
                b = notify("newer", timeout=10000)
                before = len(activated())
                assert invoke(a, a_revision) == "dispatched"
                assert activated()[before:] == [(a, "default")]
                assert snapshot(b)["summary"] == "newer"
                assert invoke(a, a_revision) == "unavailable"
                assert len(activated()) == before + 1

                # Missing actions must neither substitute another action nor close the row.
                missing = notify("no default", actions=["other", "Other"])
                revision = snapshot(missing)["revision"]
                assert invoke(missing, revision) == "unavailable"
                assert snapshot(missing)["revision"] == revision
                assert invoke(missing, revision, "other") == "dispatched"
                assert activated()[-1] == (missing, "other")

                # Even identical replacements invalidate the old inspected revision.
                replaced = notify("same", timeout=10000)
                old = snapshot(replaced)["revision"]
                assert notify("same", replace=replaced, timeout=10000) == replaced
                new = snapshot(replaced)["revision"]
                assert old != new
                before = len(activated())
                assert invoke(replaced, old) == "stale"
                assert len(activated()) == before
                assert invoke(replaced, new) == "dispatched"

                # Explicit close and transient expiry retire callbacks.
                closed = notify("closed")
                revision = snapshot(closed)["revision"]
                call("CloseNotification", "(u)", (closed,), cc=False)
                assert invoke(closed, revision) == "unavailable"
                transient = notify("transient", hints={"transient": GLib.Variant("b", True)})
                revision = snapshot(transient)["revision"]
                pump(0.3)
                assert invoke(transient, revision) == "unavailable"

                # Synchronous replacement may allocate a different desktop ID.
                hint = {"synchronous": GLib.Variant("s", "action-test-tag")}
                first = notify("sync first", hints=hint)
                first_revision = snapshot(first)["revision"]
                second = notify("sync second", hints=hint)
                assert second != first
                assert invoke(first, first_revision) == "unavailable"
                assert snapshot(second)["summary"] == "sync second"

                resident = notify("resident", hints={"resident": GLib.Variant("b", True)})
                revision = snapshot(resident)["revision"]
                pump(0.3)
                assert invoke(resident, revision) == "dispatched"
                assert snapshot(resident)["revision"] == revision
                assert call("InvokeActionWithToken", "(usss)", (resident, revision, "default", "client-token"))[0] == "dispatched"
                pump()
                assert ("ActivationToken", (resident, "client-token")) in events
                assert call("InvokeActionWithToken", "(usss)", (resident, revision, "default", "x" * 4097))[0] == "unavailable"

                # A numeric ID reused after daemon restart cannot match an old revision.
                old_id = a
                server.terminate(); server.wait(timeout=3)
                pump(0.1)
                server = start()
                reused = notify("after restart")
                assert reused == old_id
                assert invoke(reused, a_revision) == "stale"
                assert invoke(reused, snapshot(reused)["revision"]) == "dispatched"
                if client_test:
                    subprocess.run(client_test, env=env, check=True)
                print(json.dumps({"result": "passed", "checks": ["retained older card", "exact action",
                      "missing action", "identical replacement", "explicit close", "transient expiry",
                      "synchronous replacement", "resident action", "restart and ID reuse"]}))
        finally:
            os.close(read_fd)
            if server is not None and server.poll() is None:
                server.terminate(); server.wait(timeout=3)
            if compositor is not None and compositor.poll() is None:
                compositor.terminate(); compositor.wait(timeout=3)
            if compositor_log is not None:
                compositor_log.close()
            xvfb.terminate(); xvfb.wait(timeout=3)
            bus.signal_unsubscribe(subscription)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", required=True)
    parser.add_argument("--client-test", nargs=argparse.REMAINDER, default=[])
    args = parser.parse_args()
    if os.environ.get("SWAYNC_PRIVATE_ACTION_TEST") != "1":
        env = {**os.environ, "SWAYNC_PRIVATE_ACTION_TEST": "1"}
        with tempfile.TemporaryDirectory(prefix="swaync-test-bus-") as directory:
            config = Path(directory) / "bus.conf"
            config.write_text('<busconfig><type>session</type><listen>unix:tmpdir=/tmp</listen>'
                              '<auth>EXTERNAL</auth><policy context="default"><allow own="*"/>'
                              '<allow send_destination="*" eavesdrop="true"/>'
                              '<allow eavesdrop="true"/></policy></busconfig>')
            command = ["dbus-run-session", "--config-file", str(config), "--", sys.executable,
                       __file__, "--binary", str(Path(args.binary).resolve())]
            if args.client_test:
                command += ["--client-test", *args.client_test]
            raise SystemExit(subprocess.call(command, env=env))
    run(args.binary, args.client_test)

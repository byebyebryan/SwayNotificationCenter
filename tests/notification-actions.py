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


def run(binary, client_test, dashboard_screenshot=None):
    import gi
    gi.require_version("Gio", "2.0")
    from gi.repository import Gio, GLib

    assert os.environ.get("SWAYNC_PRIVATE_ACTION_TEST") == "1"
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    context = GLib.MainContext.default()
    events = []
    # An ordinary subscriber must not receive another client's action/token.
    observer = Gio.DBusConnection.new_for_address_sync(
        os.environ["DBUS_SESSION_BUS_ADDRESS"],
        Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION,
        None, None)
    observer_events = []
    observer_subscription = observer.signal_subscribe(
        None, "org.freedesktop.Notifications", None, "/org/freedesktop/Notifications", None,
        Gio.DBusSignalFlags.NONE,
        lambda _c, _s, _p, _i, member, parameters: observer_events.append((member, parameters.unpack())),
    )
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

    def call(member, signature, args, *, cc=True, connection=bus):
        return connection.call_sync(
            "org.erikreider.swaync.cc" if cc else "org.freedesktop.Notifications",
            "/org/erikreider/swaync/cc" if cc else "/org/freedesktop/Notifications",
            "org.erikreider.swaync.cc" if cc else "org.freedesktop.Notifications",
            member, GLib.Variant(signature, args), None, Gio.DBusCallFlags.NO_AUTO_START, 2000, None,
        ).unpack()

    def notify(title, *, replace=0, actions=None, hints=None, timeout=100, connection=bus):
        return call("Notify", "(susssasa{sv}i)",
                    ("action-test", replace, "", title, "body " + title,
                     ["default", "Open"] if actions is None else actions, hints or {}, timeout),
                    cc=False, connection=connection)[0]

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
            # Private ObjectManagers stand in for the system bus. GPU fixture tests
            # exercise the real query guard; this GUI test never invokes NVIDIA.
            env["DBUS_SYSTEM_BUS_ADDRESS"] = os.environ["DBUS_SESSION_BUS_ADDRESS"]
            fake_bin = root / "bin"
            fake_bin.mkdir()
            fake_smi = fake_bin / "nvidia-smi"
            fake_smi.write_text("#!/bin/sh\nprintf '%s\\n' '1200, 15, 1024, 8192'\n")
            fake_smi.chmod(0o700)
            env["PATH"] = str(fake_bin) + os.pathsep + env["PATH"]
            env["G_MESSAGES_DEBUG"] = "swaync"
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
                    packaged_style = Path(binary).resolve().parents[1] / "data/style/style.css"
                    command = [binary, "-c", str(config), "-s", str(style)]
                    if packaged_style.is_file():
                        command += ["--custom-system-css", str(packaged_style)]
                    process = subprocess.Popen(command, env=env,
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

                # Native information widgets poll only while visible, including across reloads.
                original_config = json.loads(config.read_text())
                widget_config = dict(original_config, widgets=["system-stats", "battery", "notifications"],
                                     **{"widget-config": {"system-stats": {"interval": 1},
                                                          "battery": {"interval": 1}}})

                def sample_counts():
                    text = (root / "server.log").read_text()
                    return (text.count("system-stats sample:"), text.count("battery snapshot:"))

                def widgets_ready():
                    deadline = time.monotonic() + 3
                    while time.monotonic() < deadline:
                        if min(sample_counts()) > 0:
                            return
                        pump(0.05)
                    raise AssertionError((root / "server.log").read_text())

                config.write_text(json.dumps(widget_config))
                call("ReloadConfig", "()", ())
                pump(1.2)
                assert sample_counts() == (0, 0), "hidden widgets sampled"
                call("SetVisibility", "(b)", (True,))
                widgets_ready()
                pump(2.2)
                assert min(sample_counts()) >= 3, "visible widgets did not refresh"
                before = sample_counts()
                call("ReloadConfig", "()", ())
                pump(2.2)
                after = sample_counts()
                assert all(3 <= last - first <= 4 for first, last in zip(before, after)), \
                    ("reload failed to start replacements or leaked old timers", before, after)
                call("SetVisibility", "(b)", (False,))
                pump(0.1)
                before = sample_counts()
                pump(1.2)
                assert sample_counts() == before, "closed widgets kept sampling"
                call("SetVisibility", "(b)", (True,))
                pump(0.2)
                text = (root / "server.log").read_text()
                first_cpu = [line for line in text.splitlines() if "system-stats sample:" in line][-1]
                assert "· —; RAM" in first_cpu, "reopened widget reused the hidden CPU interval"
                config.write_text(json.dumps(original_config))
                call("ReloadConfig", "()", ())
                pump(0.1)
                before = sample_counts()
                pump(1.2)
                assert sample_counts() == before, "removed widgets kept sampling"
                call("SetVisibility", "(b)", (False,))
                print(json.dumps({"result": "passed", "proof": "live widget refresh lifecycle",
                                  "checks": ["hidden idle", "visible refresh", "open reload",
                                             "close cancellation", "fresh CPU baseline", "removal cleanup"]}))

                # Exercise the nested dashboard with event-driven, private wireless services.
                fake = {
                    "nm": {
                        "/org/freedesktop/NetworkManager": {"org.freedesktop.NetworkManager": {
                            "WirelessEnabled": GLib.Variant("b", True)}},
                        "/device": {
                            "org.freedesktop.NetworkManager.Device": {"State": GLib.Variant("u", 100)},
                            "org.freedesktop.NetworkManager.Device.Wireless": {
                                "ActiveAccessPoint": GLib.Variant("o", "/ap")}},
                        "/ap": {"org.freedesktop.NetworkManager.AccessPoint": {
                            "Ssid": GLib.Variant("ay", b"A very long wireless network name"),
                            "Strength": GLib.Variant("y", 83)}},
                    },
                    "bt": {"/adapter": {"org.bluez.Adapter1": {"Powered": GLib.Variant("b", True)}}},
                }
                for index, label in enumerate(["A long Bluetooth keyboard name", "Headphones", "Mouse", "Trackpad"]):
                    fake["bt"][f"/device{index}"] = {
                        "org.bluez.Device1": {"Connected": GLib.Variant("b", True),
                                              "Alias": GLib.Variant("s", label)}}
                    if index != 1:
                        fake["bt"][f"/device{index}"]["org.bluez.Battery1"] = {
                            "Percentage": GLib.Variant("y", 0 if index == 0 else 80)}
                calls = {"nm": 0, "bt": 0}
                manager_info = Gio.DBusNodeInfo.new_for_xml('''<node>
                  <interface name="org.freedesktop.DBus.ObjectManager">
                    <method name="GetManagedObjects"><arg type="a{oa{sa{sv}}}" direction="out"/></method>
                    <signal name="InterfacesAdded"><arg type="o"/><arg type="a{sa{sv}}"/></signal>
                    <signal name="InterfacesRemoved"><arg type="o"/><arg type="as"/></signal>
                  </interface></node>''').interfaces[0]

                def managed_call(_connection, _sender, path, _interface, _method, _params, invocation):
                    key = "nm" if path == "/org/freedesktop" else "bt"
                    calls[key] += 1
                    invocation.return_value(GLib.Variant("(a{oa{sa{sv}}})", (fake[key],)))

                registrations = [bus.register_object(path, manager_info, managed_call, None, None)
                                 for path in ("/org/freedesktop", "/")]
                owners = [Gio.bus_own_name_on_connection(bus, name, Gio.BusNameOwnerFlags.NONE, None, None)
                          for name in ("org.freedesktop.NetworkManager", "org.bluez")]

                def wifi_change():
                    bus.emit_signal(None, "/ap", "org.freedesktop.DBus.Properties", "PropertiesChanged",
                                    GLib.Variant("(sa{sv}as)", (
                                        "org.freedesktop.NetworkManager.AccessPoint",
                                        fake["nm"]["/ap"]["org.freedesktop.NetworkManager.AccessPoint"], [])))

                def gpu_samples():
                    return (root / "server.log").read_text().count("gpu snapshot:")

                try:
                    pump(0.1)
                    dashboard_config = dict(original_config, widgets=["dashboard", "notifications"],
                                            **{"control-center-width": 448, "widget-config": {
                                                "system-stats": {"interval": 1}, "battery": {"interval": 1},
                                                "gpu": {"interval": 1}}})
                    config.write_text(json.dumps(dashboard_config))
                    call("ReloadConfig", "()", ())
                    pump(0.3)
                    assert calls == {"nm": 0, "bt": 0}, ("hidden dashboard read wireless data", calls)
                    before_gpu = gpu_samples()
                    call("SetVisibility", "(b)", (True,))
                    pump(1.3)
                    assert calls == {"nm": 1, "bt": 1}, calls
                    assert gpu_samples() >= before_gpu + 2, "nested GPU timer did not start"
                    if dashboard_screenshot:
                        subprocess.run(["niri", "msg", "action", "screenshot-screen", "--path",
                                        str(Path(dashboard_screenshot).resolve())], env=env, check=True,
                                       stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
                    before = calls.copy()
                    fake["nm"]["/ap"]["org.freedesktop.NetworkManager.AccessPoint"]["Strength"] = GLib.Variant("y", 55)
                    for _ in range(10):
                        wifi_change()
                    pump(0.4)
                    assert calls == {"nm": before["nm"] + 1, "bt": before["bt"]}, calls
                    del fake["bt"]["/device3"]
                    bus.emit_signal(None, "/", "org.freedesktop.DBus.ObjectManager", "InterfacesRemoved",
                                    GLib.Variant("(oas)", ("/device3", ["org.bluez.Device1", "org.bluez.Battery1"])))
                    pump(0.4)
                    assert calls["bt"] == before["bt"] + 1, calls
                    before = calls.copy()
                    call("ReloadConfig", "()", ())
                    pump(0.4)
                    assert calls == {key: value + 1 for key, value in before.items()}, calls
                    before = calls.copy()
                    wifi_change()
                    pump(0.4)
                    assert calls["nm"] == before["nm"] + 1, "reload leaked wireless subscriptions"
                    Gio.bus_unown_name(owners.pop())
                    pump(0.4)
                    owners.append(Gio.bus_own_name_on_connection(bus, "org.bluez", Gio.BusNameOwnerFlags.NONE, None, None))
                    pump(0.4)
                    assert calls["bt"] == before["bt"] + 1, "Bluetooth service restart did not refresh"
                    call("SetVisibility", "(b)", (False,))
                    pump(0.1)
                    before = calls.copy(); before_gpu = gpu_samples(); before_cpu = sample_counts()
                    wifi_change()
                    pump(1.2)
                    assert calls == before and gpu_samples() == before_gpu and sample_counts() == before_cpu, \
                        "closed dashboard retained subscriptions/timers"
                    call("SetVisibility", "(b)", (True,))
                    pump(0.4)
                    assert calls == {key: value + 1 for key, value in before.items()}
                    config.write_text(json.dumps(original_config))
                    call("ReloadConfig", "()", ())
                    pump(0.1)
                    before = calls.copy(); before_gpu = gpu_samples()
                    wifi_change(); pump(1.2)
                    assert calls == before and gpu_samples() == before_gpu, "removed dashboard retained work"
                    call("SetVisibility", "(b)", (False,))
                    print(json.dumps({"result": "passed", "proof": "two-column dashboard lifecycle",
                                      "checks": ["nested refresh", "coalesced Wi-Fi signals", "Bluetooth removal",
                                                 "service restart", "open reload", "hidden idle", "removal cleanup"]}))
                finally:
                    for owner in owners:
                        Gio.bus_unown_name(owner)
                    for registration in registrations:
                        bus.unregister_object(registration)

                # Screenshots can issue their own notifications. Start the action
                # cases with a fresh sequence so the restart ID reuse is controlled.
                server.terminate(); server.wait(timeout=3)
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
                assert not any(member in {"ActionInvoked", "ActivationToken"} for member, _ in observer_events), \
                    "an unrelated subscriber received another client's action/token"

                # A replacement's destination is its new Notify sender, even
                # when its visible text and numeric notification ID are equal.
                notify("resident", replace=resident, hints={"resident": GLib.Variant("b", True)},
                       connection=observer)
                next_revision = snapshot(resident)["revision"]
                assert next_revision != revision
                before = len(events)
                assert call("InvokeActionWithToken", "(usss)",
                            (resident, next_revision, "default", "replacement-token"))[0] == "dispatched"
                pump()
                assert not any(member in {"ActionInvoked", "ActivationToken"}
                               for member, _ in events[before:])
                assert [(member, args) for member, args in observer_events
                        if member in {"ActionInvoked", "ActivationToken"}] == [
                            ("ActivationToken", (resident, "replacement-token")),
                            ("ActionInvoked", (resident, "default")),
                        ]

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
                # Existing application processes survive a notifier restart.
                # Their old numeric IDs must not receive a different client's
                # token or action when the new daemon reuses those IDs.
                processes, terminal_logs = [], []
                classes = {name: f"swaync-restart-{name}-{os.getpid()}"
                           for name in ("old", "new", "neutral")}
                terminal = root / "restart-terminal.py"
                terminal.write_text(
                    "import sys,time\nfrom pathlib import Path\n"
                    "p=Path(sys.argv[1])\n"
                    "while not p.exists():time.sleep(.03)\n"
                    "print('\\x1b]9;'+sys.argv[2]+'\\x07',end='',flush=True)\n"
                    "time.sleep(90)\n"
                )

                def windows():
                    return json.loads(subprocess.check_output(
                        ["niri", "msg", "-j", "windows"], env=env, text=True, timeout=2))

                def wait_for(predicate):
                    deadline = time.monotonic() + 6
                    while time.monotonic() < deadline:
                        if predicate():
                            return
                        pump(0.02)
                    raise AssertionError("restart recipient proof timed out: " + repr({
                        "snapshots": [snapshot(nid) for nid in range(1, 4)],
                        "terminals": [trace(i)[-1500:] for i in range(len(terminal_logs))],
                        "processes": [process.poll() for process in processes],
                    }))

                def trace(index):
                    terminal_logs[index].flush()
                    terminal_logs[index].seek(0)
                    return terminal_logs[index].read()

                try:
                    server.terminate(); server.wait(timeout=3)
                    server = start()
                    for name in ("old", "new", "neutral"):
                        output = (root / f"restart-{name}.log").open("w+")
                        terminal_logs.append(output)
                        processes.append(subprocess.Popen(
                            ["kitty", "--debug-rendering", "--config", "NONE",
                             "-o", "linux_display_server=wayland", "--class", classes[name],
                             "--title", classes[name], "python3", str(terminal),
                             str(root / f"{name}.trigger"), f"restart-{name}"],
                            env={**env, "XDG_SESSION_TYPE": "wayland"},
                            stdout=output, stderr=subprocess.STDOUT))
                        wait_for(lambda: any(w["app_id"] == classes[name] for w in windows()))
                    wait_for(lambda: any(w["app_id"] == classes["neutral"] and w["is_focused"]
                                         for w in windows()))
                    (root / "old.trigger").touch()
                    wait_for(lambda: "restart-old" in (snapshot(1).get("summary"), snapshot(1).get("body")))
                    pump(0.1)
                    assert "Focusing window:" not in trace(0)
                    server.terminate(); server.wait(timeout=3)
                    server = start()
                    (root / "new.trigger").touch()
                    wait_for(lambda: "restart-new" in (snapshot(1).get("summary"), snapshot(1).get("body")))
                    # The same action ID now belongs to a different connection.
                    # A compositor-issued token makes accidental focus observable.
                    token_path = root / "restart-token"
                    subprocess.run(["niri", "msg", "action", "spawn", "--", "python3", "-c",
                                    "import os,sys;from pathlib import Path;"
                                    "Path(sys.argv[1]).write_text(os.environ['XDG_ACTIVATION_TOKEN'])",
                                    str(token_path)], env=env, check=True, stdout=subprocess.DEVNULL)
                    wait_for(token_path.exists)
                    token = token_path.read_text()
                    assert token
                    assert call("InvokeActionWithToken", "(usss)",
                                (1, snapshot(1)["revision"], "default", token))[0] == "dispatched"
                    wait_for(lambda: "Focusing window:" in trace(1))
                    pump(0.3)
                    assert "Focusing window:" not in trace(0), \
                        "old Kitty received the new client's action after notification ID reuse"
                    assert any(w["app_id"] == classes["new"] and w["is_focused"] for w in windows()), \
                        "the exact new originating window was not focused"
                    print(json.dumps({"result": "passed", "proof": "live Kitty clients across notifier restart",
                                      "numeric_id_reused": True, "old_client_not_activated": True,
                                      "new_originating_window_focused": True}))
                finally:
                    for process in processes:
                        if process.poll() is None:
                            process.terminate()
                    for process in processes:
                        try:
                            process.wait(timeout=3)
                        except subprocess.TimeoutExpired:
                            process.kill(); process.wait(timeout=3)
                    for output in terminal_logs:
                        output.close()
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
            observer.signal_unsubscribe(observer_subscription)
            observer.close_sync(None)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", required=True)
    parser.add_argument("--dashboard-screenshot")
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
            if args.dashboard_screenshot:
                command += ["--dashboard-screenshot", str(Path(args.dashboard_screenshot).resolve())]
            if args.client_test:
                command += ["--client-test", *args.client_test]
            raise SystemExit(subprocess.call(command, env=env))
    run(args.binary, args.client_test, args.dashboard_screenshot)

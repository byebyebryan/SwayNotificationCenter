using SwayNotificationCenter.Widgets;

Variant objects (string text) {
    try {
        return Variant.parse (new VariantType ("a{oa{sa{sv}}}"), text);
    } catch (VariantParseError e) {
        error ("Invalid test objects: %s", e.message);
    }
}

void test_wifi () {
    string fixture = "{" +
        "'/org/freedesktop/NetworkManager': {'org.freedesktop.NetworkManager': {'WirelessEnabled': <true>}},"
        +
        "'/device': {'org.freedesktop.NetworkManager.Device': {'State': <uint32 100>}," +
        "'org.freedesktop.NetworkManager.Device.Wireless': {'ActiveAccessPoint': <objectpath '/ap'>}},"
        +
        "'/ap': {'org.freedesktop.NetworkManager.AccessPoint': {'Ssid': <[byte 0x57, 0x69, 0x00, 0x46, 0x69]>, 'Strength': <byte 77>}}}";
    var wifi = WirelessData.WifiSample.parse (objects (fixture));
    assert (wifi.present && wifi.state == "Connected" && wifi.ssid == "Wi Fi" &&
            wifi.strength == 77);
    wifi = WirelessData.WifiSample.parse (objects (fixture.replace ("uint32 100", "uint32 30")));
    assert (wifi.present && wifi.state == "Disconnected" && wifi.strength == -1);
    wifi = WirelessData.WifiSample.parse (objects (fixture.replace ("uint32 100",
                                                                    "uint32 30").replace ("<true>",
                                                                                          "<false>")));
    assert (wifi.state == "Off");
    wifi = WirelessData.WifiSample.parse (objects (fixture.replace ("byte 77", "byte 255")));
    assert (wifi.strength == -1);
    assert (!WirelessData.WifiSample.parse (objects ("{}")).present);
    assert (!WirelessData.WifiSample.parse (null).present);
    assert (!WirelessData.WifiSample.parse (new Variant.string ("invalid")).present);
}

void test_bluetooth () {
    var snapshot = objects ("{" +
                            "'/adapter': {'org.bluez.Adapter1': {'Powered': <true>}}," +
                            "'/one': {'org.bluez.Device1': {'Connected': <true>, 'Alias': <'Zulu headphones'>}, 'org.bluez.Battery1': {'Percentage': <byte 0>}},"
                            +
                            "'/two': {'org.bluez.Device1': {'Connected': <true>, 'Alias': <'A very long keyboard name'>}},"
                            +
                            "'/three': {'org.bluez.Device1': {'Connected': <false>, 'Alias': <'Disconnected'>}},"
                            +
                            "'/four': {'org.bluez.Device1': {'Connected': <true>, 'Name': <'Mouse'>}, 'org.bluez.Battery1': {'Percentage': <byte 101>}}}");
    var bt = WirelessData.BluetoothSample.parse (snapshot);
    assert (bt.present && bt.powered && bt.devices.length == 3);
    assert (bt.devices[0].name == "A very long keyboard name" && bt.devices[0].battery == -1);
    assert (bt.devices[1].name == "Mouse" && bt.devices[1].battery == -1);
    assert (bt.devices[2].name == "Zulu headphones" && bt.devices[2].battery == 0);
    bt =
        WirelessData.BluetoothSample.parse (objects (
                                                "{'/adapter': {'org.bluez.Adapter1': {'Powered': <false>}}}"));
    assert (bt.present && !bt.powered && bt.devices.length == 0);
    assert (!WirelessData.BluetoothSample.parse (null).present);
    assert (!WirelessData.BluetoothSample.parse (new Variant.string ("invalid")).present);
}

void write_fixture (string root, string path, string value) {
    string target = Path.build_filename (root, path);
    DirUtils.create_with_parents (Path.get_dirname (target), 0700);
    try {
        FileUtils.set_contents (target, value);
    } catch (FileError e) {
        error ("Fixture write: %s", e.message);
    }
}

async void check_gpu (string root) throws Error {
    string pci = "0000:01:00.0";
    string path = "pci/" + pci;
    write_fixture (root, path + "/vendor", "0x10de");
    write_fixture (root, path + "/class", "0x030200");
    write_fixture (root, path + "/power/runtime_status", "suspended");
    File.new_for_path (root + "/" + path + "/driver").make_symbolic_link ("../nvidia");
    string binary = root + "/nvidia-smi";
    string calls = root + "/calls";
    write_fixture (root, "nvidia-smi",
                   "#!/bin/sh\nprintf '%s\\n' \"$*\" >> " + Shell.quote (calls) +
                   "\nprintf '%s\\n' '1200, 15, 1024, 8192'\n");
    File.new_for_path (binary).set_attribute_uint32 (FileAttribute.UNIX_MODE, 0700,
                                                     FileQueryInfoFlags.NONE);
    var reader = new GpuData.Reader (root + "/pci", binary);
    var token = new Cancellable ();
    var samples = yield reader.samples (token);

    assert (samples.length == 1 && samples[0].state == "Asleep");
    assert (!samples[0].runtime_active);
    assert (!FileUtils.test (calls, FileTest.EXISTS));
    write_fixture (root, path + "/power/runtime_status", "resuming");
    samples = yield reader.samples (token);

    assert (samples[0].state == "Unavailable" && !FileUtils.test (calls, FileTest.EXISTS));
    assert (!samples[0].runtime_active);
    write_fixture (root, path + "/power/runtime_status", "active");
    samples = yield reader.samples (token);

    assert (samples[0].state == "Active" && samples[0].clock == 1200);
    assert (samples[0].runtime_active);
    assert (samples[0].utilization == 15 && samples[0].used == 1024 && samples[0].total == 8192);
    string arguments;
    FileUtils.get_contents (calls, out arguments);
    assert (arguments.has_prefix ("--id=" + pci + " --query-gpu="));
    var invalid = new GpuData.Sample (pci);
    assert (!invalid.parse ("100, 101, 0, 8192"));
    assert (!invalid.parse ("100, 0, 9000, 8192"));
    assert (!invalid.parse ("garbage"));
    assert (invalid.parse ("[N/A], 0, 0, 8192") && invalid.clock == -1);

    // A slow CLI is bounded, killed and reaped; closing the panel cancels promptly.
    write_fixture (root, "nvidia-smi",
                   "#!/usr/bin/python3\nimport os, pathlib, time\npathlib.Path(" +
                   "'" + root + "/pid').write_text(str(os.getpid()))\ntime.sleep(30)\n");
    int64 started = get_monotonic_time ();
    samples = yield reader.samples (token);

    assert (get_monotonic_time () - started < 2500000 && samples[0].state == "Unavailable");
    assert (samples[0].runtime_active);
    string pid;
    FileUtils.get_contents (root + "/pid", out pid);
    assert (!FileUtils.test ("/proc/" + pid, FileTest.EXISTS));
    var cancelled = new Cancellable ();
    Timeout.add (100, () => { cancelled.cancel (); return Source.REMOVE; });
    started = get_monotonic_time ();
    yield reader.samples (cancelled);

    assert (get_monotonic_time () - started < 1000000);
    FileUtils.get_contents (root + "/pid", out pid);
    assert (!FileUtils.test ("/proc/" + pid, FileTest.EXISTS));
}

void test_gpu () {
    try {
        string root = DirUtils.make_tmp ("swaync-dashboard-data-XXXXXX");
        var loop = new MainLoop ();
        check_gpu.begin (root, (obj, result) => {
            try {
                check_gpu.end (result);
            } catch (Error e) {
                error ("GPU fixture: %s", e.message);
            }
            loop.quit ();
        });
        loop.run ();
        Process.spawn_command_line_sync ("rm -r -- " + Shell.quote (root));
    } catch (Error e) {
        error ("GPU fixture: %s", e.message);
    }
}

int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/dashboard/wifi", test_wifi);
    Test.add_func ("/dashboard/bluetooth", test_bluetooth);
    Test.add_func ("/dashboard/gpu", test_gpu);
    return Test.run ();
}

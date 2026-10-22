using SwayNotificationCenter.Widgets.SystemData;

void test_cpu () {
    var first = CpuTimes.parse ("cpu 100 0 100 800 0 0 0 0 1000 2000\ncpu0 1 2 3 4");
    var second = CpuTimes.parse ("cpu 150 0 150 900 0 0 0 0 9000 9000\n");
    assert (first != null && first.total == 1000 && first.idle == 800);
    assert (second != null && second.usage_since (first) == 50);
    assert (second.usage_since (null) == -1);
    assert (second.usage_since (second) == -1);
    assert (first.usage_since (second) == -1);
    assert (CpuTimes.parse ("") == null);
    assert (CpuTimes.parse ("cpu 1 nope 2 3") == null);
    assert (CpuTimes.parse ("cpu -1 0 0 1") == null);
    var decreasing_idle = CpuTimes.parse ("cpu 1000 0 0 700");
    assert (decreasing_idle.usage_since (first) == -1);
}

void test_memory_frequency () {
    var sample = new SystemSample ();
    sample.parse_memory ("MemTotal:       8388608 kB\nMemFree: 1 kB\nMemAvailable: 2097152 kB\n");
    assert (sample.memory_total_gib == 8 && sample.memory_used_gib == 6);
    var invalid = new SystemSample ();
    invalid.parse_memory ("MemTotal: 10 kB\nMemAvailable: 20 kB\n");
    assert (invalid.memory_total_gib == -1);
    assert (frequency ("processor: 0\ncpu MHz : 1000\ncpu MHz : 3000\n") == 2);
    assert (frequency ("cpu MHz: nope\n") == -1);
    assert (number ("nan") == -1 && number ("inf") == -1 && number ("invalid") == -1);
    assert (number ("") == -1 && number (" ") == -1);
}

void test_eta () {
    var sample = new BatterySample ();
    sample.state = "Discharging";
    sample.energy_now = 20000000;
    sample.energy_full = 50000000;
    sample.power = 10000000;
    assert (sample.eta () == "~02:00 to empty");
    sample.state = "Charging";
    sample.limit = 80;
    assert (sample.eta () == "~02:00 to 80%");
    sample.limit = -1;
    assert (sample.eta () == "—");
    sample.limit = 80;
    sample.energy_now = 45000000;
    assert (sample.eta () == "~00:00 to 80%");
    sample.power = 0;
    assert (sample.eta () == "—");
    sample.charge_now = 1000000;
    sample.charge_full = 5000000;
    sample.current = 1000000;
    assert (sample.eta () == "~03:00 to 80%");
    sample.state = "Not charging";
    assert (sample.eta () == "—");
    sample.state = "Full";
    assert (sample.eta () == "—");
}

void write_fixture (string root, string path, string contents) {
    string target = Path.build_filename (root, path);
    DirUtils.create_with_parents (Path.get_dirname (target), 0700);
    try {
        FileUtils.set_contents (target, contents);
    } catch (FileError e) {
        error ("Fixture write failed: %s", e.message);
    }
}

async void test_reader_async (string root) {
    var cancellable = new Cancellable ();
    var reader = new Reader (Path.build_filename (root, "proc"),
                             Path.build_filename (root, "cpu"),
                             Path.build_filename (root, "supplies"));
    write_fixture (root, "proc/stat", "cpu 100 0 100 800 0 0 0 0\n");
    write_fixture (root, "proc/meminfo", "MemTotal: 8388608 kB\nMemAvailable: 2097152 kB\n");
    write_fixture (root, "cpu/cpu0/cpufreq/scaling_cur_freq", "2000000");
    write_fixture (root, "cpu/cpu1/cpufreq/scaling_cur_freq", "3000000");
    write_fixture (root, "cpu/cpu1/online", "0");
    var system = yield reader.system (cancellable);

    assert (system.cpu.total == 1000 && system.frequency_ghz == 2);
    assert (system.memory_used_gib == 6);
    assert ((yield reader.batteries (cancellable)).length == 0);
    write_fixture (root, "supplies/BAT0/type", "Battery");
    write_fixture (root, "supplies/BAT0/status", "Charging");
    write_fixture (root, "supplies/BAT0/capacity", "20");
    write_fixture (root, "supplies/BAT0/charge_control_end_threshold", "80");
    write_fixture (root, "supplies/BAT0/current_now", "-1000000");
    write_fixture (root, "supplies/BAT0/voltage_now", "10000000");
    write_fixture (root, "supplies/BAT0/charge_now", "1000000");
    write_fixture (root, "supplies/BAT0/charge_full", "5000000");
    write_fixture (root, "supplies/mouse/type", "Battery");
    write_fixture (root, "supplies/mouse/scope", "Device");
    write_fixture (root, "supplies/absent/type", "Battery");
    write_fixture (root, "supplies/absent/present", "0");
    write_fixture (root, "supplies/AC/type", "Mains");
    var batteries = yield reader.batteries (cancellable);

    assert (batteries.length == 1 && batteries[0].name == "BAT0");
    assert (batteries[0].power == 10000000 && batteries[0].current == 1000000);
    assert (batteries[0].eta () == "~03:00 to 80%");
    write_fixture (root, "supplies/BAT0/status", "Discharging");
    write_fixture (root, "supplies/BAT0/power_now", "-5000000");
    write_fixture (root, "supplies/BAT0/energy_now", "20000000");
    write_fixture (root, "supplies/BAT1/type", "Battery");
    write_fixture (root, "supplies/BAT1/capacity", "invalid");
    batteries = yield reader.batteries (cancellable);

    assert (batteries.length == 2 && batteries[1].percentage == -1);
    assert (batteries[0].power == 5000000 && batteries[0].eta () == "~04:00 to empty");
    cancellable.cancel ();
    assert ((yield reader.batteries (cancellable)).length == 0);
}

void test_reader () {
    string root;
    try {
        root = DirUtils.make_tmp ("swaync-system-data-XXXXXX");
    } catch (FileError e) {
        error ("Fixture directory failed: %s", e.message);
    }
    var loop = new MainLoop ();
    test_reader_async.begin (root, (obj, result) => {
        test_reader_async.end (result);
        loop.quit ();
    });
    loop.run ();
    // The fixture contains no symlinks; remove only the directory created by this test.
    try {
        Process.spawn_command_line_sync ("rm -r -- " + Shell.quote (root));
    } catch (SpawnError e) {
        error ("Fixture cleanup failed: %s", e.message);
    }
}

int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/system-data/cpu", test_cpu);
    Test.add_func ("/system-data/memory-frequency", test_memory_frequency);
    Test.add_func ("/system-data/eta", test_eta);
    Test.add_func ("/system-data/reader", test_reader);
    return Test.run ();
}

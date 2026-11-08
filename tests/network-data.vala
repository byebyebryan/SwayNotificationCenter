using SwayNotificationCenter.NetworkData;

Counters counters (uint64 rx, uint64 tx) {
    var value = new Counters ();
    value.rx_bytes = rx;
    value.tx_bytes = tx;
    return value;
}

void test_counters_parse () {
    var parsed = Counters.parse (" 0\n", "\t42  ");
    assert (parsed != null && parsed.rx_bytes == 0 && parsed.tx_bytes == 42);
    parsed = Counters.parse ("18446744073709551615", "0");
    assert (parsed != null && parsed.rx_bytes == uint64.MAX);

    string ?[] invalid = { null, "", "   ", "+1", "-1", "1x", "1 2",
                           "18446744073709551616" };
    foreach (string ?text in invalid) {
        assert (Counters.parse (text, "0") == null);
        assert (Counters.parse ("0", text) == null);
    }
}

void test_tracker_rates () {
    var tracker = new Tracker ();
    var first = counters (1000, 2000);
    var sample = tracker.sample ("wlan0", first, 1000000);
    assert (sample.upload == -1 && sample.download == -1);

    sample = tracker.sample ("wlan0", counters (2000, 6000), 3000000);
    assert (sample.upload == 2000 && sample.download == 500);

    sample = tracker.sample ("wlan0", counters (2000, 6000), 4000000);
    assert (sample.upload == 0 && sample.download == 0);

    sample = tracker.sample ("wlan0", counters (2200, 6250), 4250000);
    assert (sample.upload == 1000 && sample.download == 800);

    sample = tracker.sample ("wlan1", counters (500, 900), 5250000);
    assert (sample.upload == -1 && sample.download == -1);
    sample = tracker.sample ("wlan1", counters (700, 1300), 6250000);
    assert (sample.upload == 400 && sample.download == 200);
}

void test_tracker_recovery () {
    var tracker = new Tracker ();
    var original = counters (100, 200);
    assert (tracker.sample ("eth0", original, 1000000).upload == -1);
    original.rx_bytes = uint64.MAX;
    original.tx_bytes = uint64.MAX;

    var sample = tracker.sample ("eth0", counters (300, 600), 2000000);
    assert (sample.upload == 400 && sample.download == 200);

    sample = tracker.sample ("eth0", null, 3000000);
    assert (sample.upload == -1 && sample.download == -1);
    sample = tracker.sample ("eth0", counters (400, 800), 4000000);
    assert (sample.upload == -1 && sample.download == -1);
    sample = tracker.sample ("eth0", counters (600, 1000), 5000000);
    assert (sample.upload == 200 && sample.download == 200);

    sample = tracker.sample ("eth0", counters (500, 1200), 6000000);
    assert (sample.upload == -1 && sample.download == -1);
    sample = tracker.sample ("eth0", counters (700, 1400), 7000000);
    assert (sample.upload == 200 && sample.download == 200);

    sample = tracker.sample ("eth0", counters (800, 1500), 7000000);
    assert (sample.upload == -1 && sample.download == -1);
    sample = tracker.sample ("eth0", counters (900, 1600), 6500000);
    assert (sample.upload == -1 && sample.download == -1);
    sample = tracker.sample ("eth0", counters (1000, 1700), 7500000);
    assert (sample.upload == 100 && sample.download == 100);

    tracker.reset ();
    sample = tracker.sample ("eth0", counters (1100, 1800), 8500000);
    assert (sample.upload == -1 && sample.download == -1);
    sample = tracker.sample ("eth0", counters (1200, 1900), 9500000);
    assert (sample.upload == 100 && sample.download == 100);
    sample = tracker.sample ("", counters (1300, 2000), 10500000);
    assert (sample.upload == -1 && sample.download == -1);
    sample = tracker.sample ("eth0", counters (1400, 2100), 11500000);
    assert (sample.upload == -1 && sample.download == -1);
    sample = tracker.sample ("eth0", counters (1600, 2500), 12500000);
    assert (sample.upload == 400 && sample.download == 200);
}

void test_tracker_uint64_delta () {
    var tracker = new Tracker ();
    assert (tracker.sample ("eth0", counters (0, 0), 0).upload == -1);
    var sample = tracker.sample ("eth0", counters (uint64.MAX, uint64.MAX), 1000000);
    assert (sample.upload == (double) uint64.MAX);
    assert (sample.download == (double) uint64.MAX);
}

void test_rate_formatting () {
    assert (rate (0) == "0 B/s");
    assert (rate (24) == "24 B/s");
    assert (rate (24000) == "24 KB/s");
    assert (rate (1800000) == "1.8 MB/s");
    assert (rate (999999) == "1 MB/s");
    assert (rate (-1) == "—");
    assert (rate (double.NAN) == "—");
    assert (rate (double.INFINITY) == "—");
}

void write_fixture (string root, string relative_path, string contents) {
    string path = Path.build_filename (root, relative_path);
    DirUtils.create_with_parents (Path.get_dirname (path), 0700);
    try {
        FileUtils.set_contents (path, contents);
    } catch (FileError e) {
        error ("Network fixture write failed: %s", e.message);
    }
}

async void check_reader (string root) {
    var reader = new Reader (root);
    var cancellable = new Cancellable ();
    write_fixture (root, "eth0/statistics/rx_bytes", "1234\n");
    write_fixture (root, "eth0/statistics/tx_bytes", "5678\n");

    var sample = yield reader.counters ("eth0", cancellable);

    assert (sample != null && sample.rx_bytes == 1234 && sample.tx_bytes == 5678);

    write_fixture (root, "eth0/statistics/rx_bytes", "invalid\n");
    assert ((yield reader.counters ("eth0", cancellable)) == null);
    write_fixture (root, "eth0/statistics/rx_bytes", "1234\n");
    assert ((yield reader.counters ("missing", cancellable)) == null);
    assert ((yield reader.counters ("", cancellable)) == null);
    assert ((yield reader.counters (".", cancellable)) == null);
    assert ((yield reader.counters ("..", cancellable)) == null);
    assert ((yield reader.counters ("../eth0", cancellable)) == null);
    assert ((yield reader.counters ("eth0/../eth0", cancellable)) == null);

    assert (FileUtils.remove (Path.build_filename (root, "eth0/statistics/tx_bytes")) == 0);
    assert ((yield reader.counters ("eth0", cancellable)) == null);
    write_fixture (root, "eth0/statistics/tx_bytes", "5678\n");
}

void test_reader_async () {
    string root;
    try {
        root = DirUtils.make_tmp ("swaync-network-data-XXXXXX");
    } catch (FileError e) {
        error ("Network fixture directory failed: %s", e.message);
    }
    var loop = new MainLoop ();
    check_reader.begin (root, (object, result) => {
        check_reader.end (result);
        var reader = new Reader (root);
        var cancellable = new Cancellable ();
        reader.counters.begin ("eth0", cancellable, (source, read_result) => {
            assert (reader.counters.end (read_result) == null);
            loop.quit ();
        });
        cancellable.cancel ();
    });
    loop.run ();

    assert (FileUtils.remove (Path.build_filename (root, "eth0/statistics/rx_bytes")) == 0);
    assert (FileUtils.remove (Path.build_filename (root, "eth0/statistics/tx_bytes")) == 0);
    assert (DirUtils.remove (Path.build_filename (root, "eth0/statistics")) == 0);
    assert (DirUtils.remove (Path.build_filename (root, "eth0")) == 0);
    assert (DirUtils.remove (root) == 0);
}

int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/network-data/counters-parse", test_counters_parse);
    Test.add_func ("/network-data/tracker-rates", test_tracker_rates);
    Test.add_func ("/network-data/tracker-recovery", test_tracker_recovery);
    Test.add_func ("/network-data/tracker-uint64-delta", test_tracker_uint64_delta);
    Test.add_func ("/network-data/rate-formatting", test_rate_formatting);
    Test.add_func ("/network-data/reader-async", test_reader_async);
    return Test.run ();
}

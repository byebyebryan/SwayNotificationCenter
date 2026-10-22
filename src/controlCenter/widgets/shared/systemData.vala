namespace SwayNotificationCenter.Widgets.SystemData {
    public string percentage (double value) {
        if (!value.is_finite () || value < 0 || value > 100) {
            return "—";
        }
        double rounded = Math.round (value);
        // Figure space has a tabular digit's width, unlike an ordinary space.
        return (rounded < 10 ? "\u2007" : "") + "%.0f%%".printf (rounded);
    }

    public class CpuTimes : Object {
        public uint64 total;
        public uint64 idle;

        public static CpuTimes ?parse (string contents) {
            if (contents.strip () == "") {
                return null;
            }
            string[] fields = Regex.split_simple ("\\s+", contents.strip ().split ("\n", 2)[0]);
            if (fields.length < 5 || fields[0] != "cpu") {
                return null;
            }
            var sample = new CpuTimes ();
            // Guest counters are already included in user/nice, so stop at steal.
            for (int i = 1; i < int.min (fields.length, 9); i++) {
                uint64 value = 0;
                if (fields[i].has_prefix ("-") || !uint64.try_parse (fields[i], out value)
                    || uint64.MAX - sample.total < value) {
                    return null;
                }
                sample.total += value;
                if (i == 4 || i == 5) {
                    sample.idle += value;
                }
            }
            return sample;
        }

        public double usage_since (CpuTimes ?previous) {
            if (previous == null || total <= previous.total || idle < previous.idle) {
                return -1;
            }
            uint64 elapsed = total - previous.total;
            uint64 idle_elapsed = idle - previous.idle;
            if (idle_elapsed > elapsed) {
                return -1;
            }
            return 100.0 * (elapsed - idle_elapsed) / elapsed;
        }
    }

    public class SystemSample : Object {
        public CpuTimes ?cpu;
        public double frequency_ghz = -1;
        public double memory_used_gib = -1;
        public double memory_total_gib = -1;

        public void parse_memory (string contents) {
            double total = -1;
            double available = -1;
            foreach (string line in contents.split ("\n")) {
                string[] fields = Regex.split_simple ("\\s+", line.strip ());
                if (fields.length < 3 || fields[2] != "kB") {
                    continue;
                }
                if (fields[0] == "MemTotal:") {
                    total = number (fields[1]);
                } else if (fields[0] == "MemAvailable:") {
                    available = number (fields[1]);
                }
            }
            if (total > 0 && available >= 0 && available <= total) {
                memory_total_gib = total / 1048576;
                memory_used_gib = (total - available) / 1048576;
            }
        }
    }

    public class BatterySample : Object {
        public string name;
        public string state = "Unknown";
        public double percentage = -1;
        public double limit = -1;
        public double start_threshold = -1;
        public bool external_power = false;
        public double power = -1; // microwatts
        public double current = -1; // microamps
        public double energy_now = -1; // microwatt-hours
        public double energy_full = -1;
        public double charge_now = -1; // microamp-hours
        public double charge_full = -1;

        public bool resting_on_external_power () {
            if (!external_power) {
                return false;
            }
            if (state == "Full") {
                return true;
            }
            if (state != "Not charging" || percentage < 0) {
                return false;
            }
            double target = limit > 0 && limit <= 100 ? limit : 100;
            // A stopped battery can drift through its configured charge window.
            if (limit > 0 && limit <= 100 && start_threshold >= 0 && start_threshold < limit) {
                target = start_threshold;
            }
            return percentage >= target;
        }

        public string display_state () {
            if (resting_on_external_power ()) {
                return limit > 0 && limit < 100
                    ? "At limit %.0f%%".printf (limit) : "Full";
            }
            return state;
        }

        public string eta () {
            if (state != "Charging" && state != "Discharging") {
                return "—";
            }
            if (state == "Charging" && (limit <= 0 || limit > 100)) {
                return "—";
            }
            double[] stored = { energy_now, charge_now };
            double[] full = { energy_full, charge_full };
            double[] rates = { power, current };
            for (int i = 0; i < stored.length; i++) {
                if (stored[i] < 0 || rates[i] <= 0 || (state == "Charging" && full[i] <= 0)) {
                    continue;
                }
                double remaining = stored[i];
                if (state == "Charging") {
                    remaining = double.max (0, full[i] * limit / 100 - remaining);
                }
                double minutes = Math.round (60 * remaining / rates[i]);
                if (!minutes.is_finite () || minutes > int.MAX) {
                    continue;
                }
                int value = (int) minutes;
                string target = state == "Discharging" ? "empty" : "%.0f%%".printf (limit);
                return "~%02d:%02d to %s".printf (value / 60, value % 60, target);
            }
            return "—";
        }
    }

    public double number (string contents) {
        double value;
        // Vala's double.try_parse accepts an empty string as zero.
        if (contents.strip () == "") {
            return -1;
        }
        return double.try_parse (contents, out value) && value.is_finite () ? value : -1;
    }

    public double frequency (string contents) {
        double total = 0;
        int count = 0;
        foreach (string line in contents.split ("\n")) {
            string[] parts = line.split (":", 2);
            if (parts.length == 2 && parts[0].strip () == "cpu MHz") {
                double value = number (parts[1].strip ());
                if (value > 0) {
                    total += value;
                    count++;
                }
            }
        }
        return count > 0 ? total / count / 1000 : -1;
    }

    public class Reader : Object {
        string proc_root;
        string cpu_root;
        string supply_root;

        public Reader (string proc_root = "/proc",
                       string cpu_root = "/sys/devices/system/cpu",
                       string supply_root = "/sys/class/power_supply") {
            this.proc_root = proc_root;
            this.cpu_root = cpu_root;
            this.supply_root = supply_root;
        }

        async string read (string path, Cancellable cancellable) {
            if (cancellable.is_cancelled ()) {
                return "";
            }
            try {
                uint8[] contents;
                yield File.new_for_path (path).load_contents_async (cancellable, out contents,
                                                                    null);

                return ((string) contents).strip ();
            } catch (Error e) {
                // Missing/unsupported attributes are normal across machines and battery drivers.
                return "";
            }
        }

        string[] children (string path) {
            var names = new GenericArray<string> ();
            try {
                var directory = Dir.open (path);
                string ?name;
                while ((name = directory.read_name ()) != null) {
                    names.add (name);
                }
            } catch (FileError e) {
                return {};
            }
            names.sort ((a, b) => strcmp (a, b));
            return names.data;
        }

        public async SystemSample system (Cancellable cancellable) {
            var sample = new SystemSample ();
            sample.cpu = CpuTimes.parse (yield read (Path.build_filename (proc_root, "stat"),
                                                     cancellable));
            sample.parse_memory (yield read (Path.build_filename (proc_root, "meminfo"),
                                             cancellable));
            sample.frequency_ghz = frequency (yield read (Path.build_filename (proc_root,
                                                                               "cpuinfo"),
                                                          cancellable));
            if (sample.frequency_ghz <= 0) {
                double total = 0;
                int count = 0;
                foreach (string name in children (cpu_root)) {
                    if (!Regex.match_simple ("^cpu[0-9]+$", name)) {
                        continue;
                    }
                    string path = Path.build_filename (cpu_root, name);
                    if ((yield read (Path.build_filename (path, "online"), cancellable)) == "0") {
                        continue;
                    }
                    double value = number (yield read (Path.build_filename (path, "cpufreq",
                                                                            "scaling_cur_freq"),
                                                       cancellable));
                    if (value > 0) {
                        total += value;
                        count++;
                    }
                }
                sample.frequency_ghz = count > 0 ? total / count / 1000000 : -1;
            }
            return sample;
        }

        public async BatterySample[] batteries (Cancellable cancellable) {
            var samples = new GenericArray<BatterySample> ();
            string[] supplies = children (supply_root);
            bool external_power = false;
            foreach (string name in supplies) {
                if (cancellable.is_cancelled ()) {
                    break;
                }
                string path = Path.build_filename (supply_root, name);
                string type = yield read (Path.build_filename (path, "type"), cancellable);

                if (type != "" && type != "Battery"
                    && (yield read (Path.build_filename (path, "scope"), cancellable)) != "Device"
                    && (yield read (Path.build_filename (path, "online"), cancellable)) == "1") {
                    external_power = true;
                    break;
                }
            }
            foreach (string name in supplies) {
                if (cancellable.is_cancelled ()) {
                    break;
                }
                string path = Path.build_filename (supply_root, name);
                if ((yield read (Path.build_filename (path, "type"), cancellable)) != "Battery"
                    || (yield read (Path.build_filename (path, "scope"), cancellable)) == "Device"
                    || (yield read (Path.build_filename (path, "present"), cancellable)) == "0") {
                    continue;
                }
                var sample = new BatterySample ();
                sample.name = name;
                sample.external_power = external_power;
                string state = yield read (Path.build_filename (path, "status"), cancellable);

                if (state in new string[] { "Charging", "Discharging", "Full", "Not charging" }) {
                    sample.state = state;
                }
                double capacity = number (yield read (Path.build_filename (path, "capacity"),
                                                      cancellable));
                sample.percentage = capacity >= 0 && capacity <= 100 ? capacity : -1;
                double limit = number (yield read (Path.build_filename (path,
                                                                        "charge_control_end_threshold"),
                                                   cancellable));
                sample.limit = limit > 0 && limit <= 100 ? limit : -1;
                double start = number (yield read (Path.build_filename (path,
                                                                        "charge_control_start_threshold"),
                                                   cancellable));
                sample.start_threshold = start >= 0 && start <= 100 ? start : -1;
                string current = yield read (Path.build_filename (path, "current_now"),
                                             cancellable);

                double value = 0;
                // Signed driver readings describe direction; status supplies the label.
                if (current != "" && double.try_parse (current, out value) && value.is_finite ()) {
                    sample.current = value.abs ();
                }
                string power = yield read (Path.build_filename (path, "power_now"), cancellable);

                if (power != "" && double.try_parse (power, out value) && value.is_finite ()) {
                    sample.power = value.abs ();
                } else {
                    double voltage = number (yield read (Path.build_filename (path, "voltage_now"),
                                                         cancellable));
                    if (sample.current >= 0 && voltage > 0) {
                        sample.power = sample.current * voltage / 1000000;
                    }
                }
                sample.energy_now = number (yield read (Path.build_filename (path, "energy_now"),
                                                        cancellable));
                sample.energy_full = number (yield read (Path.build_filename (path, "energy_full"),
                                                         cancellable));
                sample.charge_now = number (yield read (Path.build_filename (path, "charge_now"),
                                                        cancellable));
                sample.charge_full = number (yield read (Path.build_filename (path, "charge_full"),
                                                         cancellable));
                samples.add (sample);
            }
            return samples.data;
        }
    }
}

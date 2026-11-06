namespace SwayNotificationCenter.NetworkData {
    public class Counters : Object {
        public uint64 rx_bytes;
        public uint64 tx_bytes;

        public static Counters ?parse (string ?rx, string ?tx) {
            uint64 received = 0;
            uint64 transmitted = 0;
            if (!parse_counter (rx, out received) || !parse_counter (tx, out transmitted)) {
                return null;
            }

            var counters = new Counters ();
            counters.rx_bytes = received;
            counters.tx_bytes = transmitted;
            return counters;
        }

        static bool parse_counter (string ?text, out uint64 value) {
            value = 0;
            if (text == null) {
                return false;
            }

            string trimmed = text.strip ();
            if (trimmed == "") {
                return false;
            }
            for (int i = 0; i < trimmed.length; i++) {
                if (!trimmed[i].isdigit ()) {
                    return false;
                }
            }
            return uint64.try_parse (trimmed, out value);
        }
    }

    public class RateSample : Object {
        public double upload = -1;
        public double download = -1;
    }

    public class Tracker : Object {
        bool has_baseline = false;
        string interface_name = "";
        uint64 rx_bytes;
        uint64 tx_bytes;
        int64 time_us;

        public void reset () {
            has_baseline = false;
            interface_name = "";
            rx_bytes = 0;
            tx_bytes = 0;
            time_us = 0;
        }

        public RateSample sample (string interface_name, Counters ?counters, int64 now_us) {
            var unavailable = new RateSample ();
            if (interface_name == "" || counters == null) {
                reset ();
                return unavailable;
            }

            uint64 current_rx = counters.rx_bytes;
            uint64 current_tx = counters.tx_bytes;
            if (!has_baseline || this.interface_name != interface_name) {
                set_baseline (interface_name, current_rx, current_tx, now_us);
                return unavailable;
            }

            if (now_us <= time_us || current_rx < rx_bytes || current_tx < tx_bytes) {
                set_baseline (interface_name, current_rx, current_tx, now_us);
                return unavailable;
            }

            uint64 elapsed_us = elapsed_microseconds (time_us, now_us);
            if (elapsed_us == 0) {
                set_baseline (interface_name, current_rx, current_tx, now_us);
                return unavailable;
            }

            double elapsed_seconds = (double) elapsed_us / 1000000.0;
            var rates = new RateSample ();
            rates.upload = (double) (current_tx - tx_bytes) / elapsed_seconds;
            rates.download = (double) (current_rx - rx_bytes) / elapsed_seconds;
            set_baseline (interface_name, current_rx, current_tx, now_us);
            return rates;
        }

        void set_baseline (string interface_name, uint64 rx_bytes, uint64 tx_bytes,
                           int64 time_us) {
            this.interface_name = interface_name;
            this.rx_bytes = rx_bytes;
            this.tx_bytes = tx_bytes;
            this.time_us = time_us;
            has_baseline = true;
        }

        static uint64 elapsed_microseconds (int64 earlier, int64 later) {
            if (earlier >= 0) {
                return (uint64) later - (uint64) earlier;
            }
            if (later < 0) {
                return (uint64) (later - earlier);
            }

            int64 adjusted_earlier = earlier + 1;
            uint64 earlier_magnitude = (uint64) (0 - adjusted_earlier) + 1;
            return earlier_magnitude + (uint64) later;
        }
    }

    public string rate (double bytes_per_second) {
        if (!bytes_per_second.is_finite () || bytes_per_second < 0) {
            return "—";
        }
        if (bytes_per_second == 0) {
            return "0 B/s";
        }

        string[] units = { "B/s", "KB/s", "MB/s", "GB/s", "TB/s" };
        double value = bytes_per_second;
        int unit = 0;
        while (value >= 1000.0 && unit < units.length - 1) {
            value /= 1000.0;
            unit++;
        }

        double rounded = value < 10.0
            ? Math.round (value * 10.0) / 10.0 : Math.round (value);
        if (rounded >= 1000.0 && unit < units.length - 1) {
            value /= 1000.0;
            unit++;
        }

        char[] buffer = new char[double.DTOSTR_BUF_SIZE];
        string formatted = value.format (buffer, value < 10.0 ? "%.1f" : "%.0f");
        if (formatted.has_suffix (".0")) {
            formatted = formatted.substring (0, formatted.length - 2);
        }
        return "%s %s".printf (formatted, units[unit]);
    }

    public class Reader : Object {
        string sys_root;

        public Reader (string sys_root = "/sys/class/net") {
            this.sys_root = sys_root;
        }

        async string ?read (string path, Cancellable cancellable) {
            if (cancellable.is_cancelled ()) {
                return null;
            }
            try {
                uint8[] contents;
                bool loaded = yield File.new_for_path (path).load_contents_async (
                    cancellable, out contents, null);

                if (!loaded || cancellable.is_cancelled () || contents == null) {
                    return null;
                }
                for (int i = 0; i < contents.length; i++) {
                    if (contents[i] == 0) {
                        return null;
                    }
                }
                return ((string) contents).strip ();
            } catch (Error e) {
                return null;
            }
        }

        public async Counters ?counters (string interface_name, Cancellable cancellable) {
            if (interface_name == "" || interface_name == "." || interface_name == ".." ||
                interface_name.contains ("/")) {
                return null;
            }

            string statistics = Path.build_filename (sys_root, interface_name, "statistics");
            string ?rx = yield read (Path.build_filename (statistics, "rx_bytes"), cancellable);

            if (rx == null || cancellable.is_cancelled ()) {
                return null;
            }
            string ?tx = yield read (Path.build_filename (statistics, "tx_bytes"), cancellable);

            if (tx == null || cancellable.is_cancelled ()) {
                return null;
            }
            return Counters.parse (rx, tx);
        }
    }
}

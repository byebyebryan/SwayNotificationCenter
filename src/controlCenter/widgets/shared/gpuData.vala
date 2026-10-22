namespace SwayNotificationCenter.Widgets.GpuData {
    public class Sample : Object {
        public string pci;
        public string state = "Unavailable";
        public bool runtime_active = false;
        public double clock = -1;
        public double utilization = -1;
        public double used = -1;
        public double total = -1;

        public Sample (string pci) {
            this.pci = pci;
        }

        public bool parse (string output) {
            string[] fields = output.strip ().split (",");
            if (fields.length != 4) {
                return false;
            }
            clock = SystemData.number (fields[0].strip ());
            utilization = SystemData.number (fields[1].strip ());
            used = SystemData.number (fields[2].strip ());
            total = SystemData.number (fields[3].strip ());
            if (utilization < 0 || utilization > 100 || used < 0 || total <= 0 || used > total) {
                return false;
            }
            state = "Active";
            return true;
        }
    }

    public class Reader : Object {
        string root;
        string binary;

        public Reader (string root = "/sys/bus/pci/devices", string binary = "nvidia-smi") {
            this.root = root;
            this.binary = binary;
        }

        async string read (string path, Cancellable cancellable) {
            try {
                uint8[] bytes;
                yield File.new_for_path (path).load_contents_async (cancellable, out bytes, null);

                return ((string) bytes).strip ();
            } catch (Error e) {
                return "";
            }
        }

        async void query (Sample sample, Cancellable cancellable) {
            if (cancellable.is_cancelled ()) {
                return;
            }
            try {
                var process = new Subprocess.newv ({ binary, "--id=" + sample.pci,
                                                     "--query-gpu=clocks.current.graphics,utilization.gpu,memory.used,memory.total",
                                                     "--format=csv,noheader,nounits" },
                                                   SubprocessFlags.STDOUT_PIPE |
                                                   SubprocessFlags.STDERR_SILENCE);
                var query_cancel = new Cancellable ();
                ulong handler = cancellable.connect (() => {
                    process.force_exit ();
                    query_cancel.cancel ();
                });
                uint timeout = Timeout.add (1000, () => {
                    process.force_exit ();
                    query_cancel.cancel ();
                    return Source.REMOVE;
                });
                try {
                    string output;
                    yield process.communicate_utf8_async (null, query_cancel, out output, null);

                    if (!cancellable.is_cancelled () && process.get_successful () &&
                        output.length <= 4096) {
                        sample.parse (output);
                    }
                } catch (Error e) {
                    process.force_exit ();
                    yield process.wait_async (null);
                } finally {
                    // A fired timeout has already removed itself.
                    if (MainContext.default ().find_source_by_id (timeout) != null) {
                        Source.remove (timeout);
                    }
                    cancellable.disconnect (handler);
                }
            } catch (Error e) {
                // Missing CLI, device disappearance and cancelled reads are ordinary unavailable data.
            }
        }

        public async Sample[] samples (Cancellable cancellable) {
            var samples = new GenericArray<Sample> ();
            var names = new GenericArray<string> ();
            try {
                var directory = Dir.open (root);
                string ?name;
                while ((name = directory.read_name ()) != null) {
                    names.add (name);
                }
            } catch (FileError e) {
                return {};
            }
            names.sort ((a, b) => strcmp (a, b));
            foreach (string name in names.data) {
                if (cancellable.is_cancelled ()) {
                    break;
                }
                if (!Regex.match_simple ("^[0-9a-fA-F]{4}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\\.[0-7]$",
                                         name)) {
                    continue;
                }
                string path = Path.build_filename (root, name);
                if ((yield read (path + "/vendor", cancellable)) != "0x10de"
                    || !(yield read (path + "/class", cancellable)).has_prefix ("0x03")) {
                    continue;
                }
                try {
                    string driver = FileUtils.read_link (path + "/driver");
                    if (Path.get_basename (driver) != "nvidia") {
                        continue;
                    }
                } catch (FileError e) {
                    continue;
                }
                var sample = new Sample (name);
                // Cached PCI state does not touch the NVIDIA query interface. The state can
                // still change between this check and the targeted query, as in Rofi.
                string state = yield read (path + "/power/runtime_status", cancellable);

                if (state == "suspended" || state == "suspending") {
                    sample.state = "Asleep";
                } else if (state == "active") {
                    sample.runtime_active = true;
                    yield query (sample, cancellable);
                }
                samples.add (sample);
            }
            return samples.data;
        }
    }
}

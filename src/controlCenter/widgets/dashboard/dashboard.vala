namespace SwayNotificationCenter.Widgets {
    public class Dashboard : BaseWidget {
        public override string widget_name { get {
                                                 return "dashboard";
                                             } }
        Gtk.Grid grid = new Gtk.Grid ();
        BaseWidget[] cards;
        ulong[] visibility_handlers = {};

        public Dashboard (string suffix) {
            base (suffix);
            grid.column_homogeneous = true;
            grid.column_spacing = 12;
            grid.row_spacing = 12;
            grid.hexpand = true;
            cards = { new SystemStats (suffix, true), new Battery (suffix, true),
                      new Wifi (suffix), new Bluetooth (suffix) };
            for (int i = 0; i < cards.length; i++) {
                cards[i].add_css_class ("dashboard-card");
                cards[i].hexpand = true;
                grid.attach (cards[i], i % 2, i / 2);
                visibility_handlers += cards[i].notify["visible"].connect (reflow);
            }
            append (grid);
            reflow ();
        }

        void reflow () {
            int count = 0;
            foreach (var card in cards) {
                if (card.visible) {
                    count++;
                }
            }
            int index = 0;
            foreach (var card in cards) {
                if (!card.visible) {
                    continue;
                }
                // Change grid metadata without reparenting: unroot would cancel card work.
                var child =
                    (Gtk.GridLayoutChild) grid.get_layout_manager ().get_layout_child (card);
                child.column = index % 2;
                child.row = index / 2;
                child.column_span = index == count - 1 && count % 2 == 1 ? 2 : 1;
                index++;
            }
        }

        public override void on_cc_visibility_change (bool visible) {
            foreach (var card in cards) {
                card.on_cc_visibility_change (visible);
            }
        }

        public override void unroot () {
            on_cc_visibility_change (false);
            for (int i = 0; i < visibility_handlers.length; i++) {
                cards[i].disconnect (visibility_handlers[i]);
            }
            visibility_handlers = {};
            base.unroot ();
        }
    }

    public class GpuStats : PollingWidget {
        public override string widget_name { get {
                                                 return "gpu";
                                             } }
        GpuData.Reader reader = new GpuData.Reader ();
        Gtk.Grid grid = new Gtk.Grid ();
        string identity = "";
        Gtk.Label[] gpu_values = {};
        Gtk.Label[] memory_values = {};

        public GpuStats (string suffix) {
            base (suffix);
            configure_interval (2);
            grid.column_spacing = 6;
            grid.row_spacing = 8;
            grid.hexpand = true;
            append (grid);
            visible = false;
        }

        protected override async void update_sample (Cancellable cancellable) {
            var samples = yield reader.samples (cancellable);

            if (cancellable.is_cancelled ()) {
                return;
            }
            string key = "";
            foreach (var sample in samples) {
                key += sample.pci + ";";
            }
            if (key != identity) {
                identity = key;
                Gtk.Widget ?child;
                while ((child = grid.get_first_child ()) != null) {
                    grid.remove (child);
                }
                gpu_values = {};
                memory_values = {};
                for (int i = 0; i < samples.length; i++) {
                    string suffix = samples.length > 1 ? " %d".printf (i + 1) : "";
                    gpu_values += add_metric (grid, i * 2, "GPU" + suffix);
                    memory_values += add_metric (grid, i * 2 + 1, "VRAM" + suffix);
                }
            }
            for (int i = 0; i < samples.length; i++) {
                var sample = samples[i];
                gpu_values[i].label = sample.state;
                memory_values[i].label = "—";
                gpu_values[i].tooltip_text = sample.pci + " · " + sample.state;
                memory_values[i].tooltip_text = null;
                if (sample.state == "Active") {
                    string clock = sample.clock >=
                        0 ? "%.1f GHz".printf (sample.clock / 1000) : "—";
                    gpu_values[i].label = "%s · %.0f%%".printf (clock, sample.utilization);
                    memory_values[i].label = "%.1f GiB · %.0f%%".printf (sample.used / 1024,
                                                                         100 * sample.used /
                                                                         sample.total);
                    memory_values[i].tooltip_text = "%.1f / %.1f GiB".printf (sample.used / 1024,
                                                                              sample.total / 1024);
                }
            }
            visible = samples.length > 0;
            debug ("gpu snapshot: %d devices", samples.length);
        }
    }

    public class Wifi : BusWidget {
        public override string widget_name { get {
                                                 return "wifi";
                                             } }
        Gtk.Label network_name;
        Gtk.Label strength;

        public Wifi (string suffix) {
            base (suffix, "org.freedesktop.NetworkManager", "/org/freedesktop");
            add_heading ("Wi-Fi");
            var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            network_name = new Gtk.Label ("—");
            network_name.xalign = 0;
            network_name.hexpand = true;
            network_name.ellipsize = Pango.EllipsizeMode.END;
            network_name.max_width_chars = 1;
            strength = new Gtk.Label ("");
            strength.add_css_class ("metric-value");
            row.append (network_name);
            row.append (strength);
            append (row);
        }

        protected override bool watches_interface (string iface) {
            return iface in new string[] { "org.freedesktop.NetworkManager",
                                           "org.freedesktop.NetworkManager.Device",
                                           "org.freedesktop.NetworkManager.Device.Wireless",
                                           "org.freedesktop.NetworkManager.AccessPoint" };
        }

        protected override void apply_snapshot (Variant ?objects) {
            var sample = WirelessData.WifiSample.parse (objects);
            network_name.label = sample.state == "Connected" ? sample.ssid : sample.state;
            network_name.tooltip_text = network_name.label;
            strength.label = sample.strength >= 0 ? "%d%%".printf (sample.strength) : "";
            visible = sample.present;
        }
    }

    public class Bluetooth : BusWidget {
        public override string widget_name { get {
                                                 return "bluetooth";
                                             } }
        Gtk.Box devices = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
        Gtk.Button more = new Gtk.Button ();
        WirelessData.BluetoothSample ?sample;
        bool expanded = false;

        public Bluetooth (string suffix) {
            base (suffix, "org.bluez", "/");
            add_heading ("Bluetooth");
            append (devices);
            more.add_css_class ("flat");
            more.add_css_class ("bluetooth-more");
            more.clicked.connect (() => {
                expanded = !expanded;
                rebuild ();
            });
            append (more);
        }

        protected override bool watches_interface (string iface) {
            return iface in new string[] { "org.bluez.Adapter1", "org.bluez.Device1",
                                           "org.bluez.Battery1" };
        }

        protected override void apply_snapshot (Variant ?objects) {
            sample = WirelessData.BluetoothSample.parse (objects);
            rebuild ();
            visible = sample.present;
        }

        void rebuild () {
            if (sample == null) {
                return;
            }
            Gtk.Widget ?child;
            while ((child = devices.get_first_child ()) != null) {
                devices.remove (child);
            }
            if (sample.devices.length == 0) {
                var label = new Gtk.Label (sample.powered ? "No devices connected" : "Off");
                label.xalign = 0;
                label.wrap = true;
                devices.append (label);
            }
            int count = (int) sample.devices.length;
            for (int i = 0; i < (expanded ? count : int.min (count, 2)); i++) {
                var entry = sample.devices[i];
                var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
                var label = new Gtk.Label (entry.name);
                label.xalign = 0;
                label.hexpand = true;
                label.max_width_chars = 1;
                label.ellipsize = Pango.EllipsizeMode.END;
                label.tooltip_text = entry.name;
                row.append (label);
                if (entry.battery >= 0) {
                    var percentage = new Gtk.Label ("%d%%".printf (entry.battery));
                    percentage.add_css_class ("metric-value");
                    row.append (percentage);
                }
                devices.append (row);
            }
            more.visible = count > 2;
            more.label = expanded ? "Show less" : "+%d more".printf (count - 2);
        }

        public override void on_cc_visibility_change (bool visible) {
            if (!visible) {
                expanded = false;
                rebuild ();
            }
            base.on_cc_visibility_change (visible);
        }
    }
}

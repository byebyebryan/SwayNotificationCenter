namespace SwayNotificationCenter.Widgets {
    public class Dashboard : BaseWidget {
        public override string widget_name { get {
                                                 return "dashboard";
                                             } }
        BaseWidget[] cards;

        public Dashboard (string suffix) {
            base (suffix);
            orientation = Gtk.Orientation.VERTICAL;
            spacing = 12;
            cards = { new SystemStats (suffix, true), new Network (suffix),
                      new Bluetooth (suffix), new Battery (suffix, true) };
            for (int i = 0; i < cards.length; i++) {
                cards[i].add_css_class ("dashboard-card");
                cards[i].hexpand = true;
                append (cards[i]);
            }
        }

        public override void on_cc_visibility_change (bool visible) {
            foreach (var card in cards) {
                card.on_cc_visibility_change (visible);
            }
        }

        public override void unroot () {
            on_cc_visibility_change (false);
            base.unroot ();
        }
    }

    public class GpuStats : PollingWidget {
        public override string widget_name { get {
                                                 return "gpu";
                                             } }
        GpuData.Reader reader = new GpuData.Reader ();
        Gtk.Box rows = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
        string identity = "";
        Gtk.Label[] gpu_values = {};
        Gtk.Label[] memory_values = {};
        InformationMeter[] gpu_meters = {};
        InformationMeter[] memory_meters = {};
        bool information;

        public GpuStats (string suffix, bool information = false) {
            base (suffix);
            this.information = information;
            configure_interval (2);
            rows.hexpand = true;
            append (rows);
            visible = false;
        }

        protected override void reset_sample () {
            visible = false;
        }

        protected override async void update_sample (Cancellable cancellable) {
            var readings = yield reader.samples (cancellable);

            if (cancellable.is_cancelled ()) {
                return;
            }
            apply_samples (readings);
        }

        internal void apply_samples (GpuData.Sample[] readings) {
            var active = new GenericArray<GpuData.Sample> ();
            foreach (var sample in readings) {
                if (sample.runtime_active) {
                    active.add (sample);
                }
            }
            var samples = active.data;
            string key = "";
            foreach (var sample in samples) {
                key += sample.pci + ";";
            }
            if (information) {
                apply_information_samples (samples, key);
                return;
            }
            if (key != identity) {
                identity = key;
                Gtk.Widget ?child;
                while ((child = rows.get_first_child ()) != null) {
                    rows.remove (child);
                }
                gpu_values = {};
                memory_values = {};
                for (int i = 0; i < samples.length; i++) {
                    string suffix = samples.length > 1 ? " %d".printf (i + 1) : "";
                    var columns = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 20);
                    columns.homogeneous = true;
                    columns.hexpand = true;
                    var graphics = new Gtk.Grid ();
                    var memory = new Gtk.Grid ();
                    graphics.column_spacing = memory.column_spacing = 6;
                    graphics.hexpand = memory.hexpand = true;
                    gpu_values += add_metric (graphics, 0, "GPU" + suffix);
                    memory_values += add_metric (memory, 0, "VRAM" + suffix);
                    columns.append (graphics);
                    columns.append (memory);
                    rows.append (columns);
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
                    gpu_values[i].label = "%s · %s".printf (clock,
                                                            SystemData.percentage (
                                                                sample.utilization));
                    string memory_percentage = SystemData.percentage (
                        100 * sample.used / sample.total);
                    memory_values[i].label = "%.1f GiB · %s".printf (
                        sample.used / 1024, memory_percentage);
                    string tooltip = "%.1f / %.1f GiB".printf (
                        sample.used / 1024, sample.total / 1024);
                    memory_values[i].tooltip_text = tooltip;
                }
            }
            visible = samples.length > 0;
            debug ("gpu snapshot: %d active of %d devices", samples.length, readings.length);
        }

        void apply_information_samples (GpuData.Sample[] samples, string key) {
            if (key != identity) {
                identity = key;
                Gtk.Widget ?child;
                while ((child = rows.get_first_child ()) != null) {
                    rows.remove (child);
                }
                gpu_meters = {};
                memory_meters = {};
                for (int i = 0; i < samples.length; i++) {
                    string suffix = samples.length > 1 ? " %d".printf (i + 1) : "";
                    var columns = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 20);
                    columns.homogeneous = true;
                    columns.hexpand = true;
                    var graphics = new InformationMeter ("GPU" + suffix);
                    var memory = new InformationMeter ("VRAM" + suffix);
                    graphics.hexpand = memory.hexpand = true;
                    gpu_meters += graphics;
                    memory_meters += memory;
                    columns.append (graphics);
                    columns.append (memory);
                    rows.append (columns);
                }
            }
            for (int i = 0; i < samples.length; i++) {
                var sample = samples[i];
                string clock = sample.clock >= 0
                    ? "%.1f GHz".printf (sample.clock / 1000) : "";
                string memory = sample.total > 0 && sample.used >= 0 && sample.used <= sample.total
                    ? "%.1f / %.0f GiB".printf (sample.used / 1024, sample.total / 1024) : "";
                gpu_meters[i].set_reading (sample.state == "Active" ? sample.utilization : -1,
                                           clock);
                memory_meters[i].set_reading (
                    sample.state == "Active" && sample.total > 0 && sample.used >= 0
                    ? 100 * sample.used / sample.total : -1, memory);
                gpu_meters[i].set_tooltip_text (sample.pci + " · " + sample.state);
                memory_meters[i].set_tooltip_text (sample.pci + " · " + sample.state);
            }
            visible = samples.length > 0;
            debug ("gpu information snapshot: %d active devices", samples.length);
        }
    }

    public class Network : BusWidget {
        public override string widget_name { get {
                                                 return "network";
                                             } }
        Gtk.Label network_name;
        Gtk.Label network_label;
        Gtk.Label strength;
        Gtk.Box signal_row;
        bool information;
        Gtk.Box ?information_left = null;
        Gtk.Box ?information_columns = null;
        Gtk.Label ?information_detail_label = null;
        Gtk.Widget ?information_icon = null;
        NetworkActivity ?activity = null;

        public Network (string suffix, bool information = false) {
            base (suffix, "org.freedesktop.NetworkManager", "/org/freedesktop");
            this.information = information;
            if (!information) {
                add_heading ("Network");
            }
            var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 20);
            row.homogeneous = true;
            row.hexpand = true;
            network_name = new Gtk.Label ("—");
            network_name.xalign = information ? 0 : 1;
            network_name.hexpand = true;
            network_name.ellipsize = Pango.EllipsizeMode.END;
            network_name.single_line_mode = true;
            network_name.max_width_chars = 1;
            network_name.add_css_class ("metric-value");
            var network_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            network_label = new Gtk.Label ("NET");
            network_label.add_css_class ("metric-label");
            network_row.append (network_label);
            network_row.append (network_name);
            strength = new Gtk.Label ("");
            strength.xalign = 1;
            strength.hexpand = true;
            strength.add_css_class ("metric-value");
            if (information) {
                strength.ellipsize = Pango.EllipsizeMode.END;
                strength.max_width_chars = 1;
                strength.single_line_mode = true;
                strength.add_css_class ("information-connection-value");
            }
            signal_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            var signal_label = new Gtk.Label ("Signal");
            signal_label.add_css_class ("metric-label");
            signal_row.append (signal_label);
            if (information) {
                network_row.add_css_class ("information-connection-name");
                network_name.xalign = 0;
                information_left = network_row;
                information_columns = row;
                row.add_css_class ("information-connection-columns");
                information_detail_label = signal_label;
                signal_label.add_css_class ("information-connection-label");
                signal_row.add_css_class ("information-connection-details");
                signal_row.append (strength);
                network_label.visible = false;
                information_icon = InformationIcons.symbol ("network-transmit-receive-symbolic",
                                                            "network-transmit-receive",
                                                            "Network");
                network_row.prepend (information_icon);
                var connection_cell = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
                connection_cell.hexpand = true;
                connection_cell.valign = Gtk.Align.START;
                connection_cell.add_css_class ("information-connection-cell");
                connection_cell.append (network_row);
                connection_cell.append (signal_row);
                activity = new NetworkActivity (suffix);
                strength.label = "—";
                strength.add_css_class ("information-connection-value");
                row.append (connection_cell);
                row.append (activity);
            } else {
                signal_row.append (strength);
                // Keep the second column allocated when its Wi-Fi content is hidden.
                var signal_cell = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
                signal_row.hexpand = true;
                signal_cell.append (signal_row);
                row.append (network_row);
                row.append (signal_cell);
            }
            append (row);
        }

        protected void replace_activity_widget (NetworkActivity replacement) {
            if (activity != null) {
                activity.on_cc_visibility_change (false);
                information_columns.remove (activity);
            }
            activity = replacement;
            information_columns.append (activity);
        }

        public override void on_cc_visibility_change (bool visible) {
            base.on_cc_visibility_change (visible);
            if (activity != null) {
                activity.on_cc_visibility_change (visible);
            }
        }

        public override void unroot () {
            if (activity != null) {
                activity.on_cc_visibility_change (false);
            }
            base.unroot ();
        }

        protected override bool watches_interface (string iface) {
            return iface in new string[] { "org.freedesktop.NetworkManager",
                                           "org.freedesktop.NetworkManager.Connection.Active",
                                           "org.freedesktop.NetworkManager.Device",
                                           "org.freedesktop.NetworkManager.Device.Wired",
                                           "org.freedesktop.NetworkManager.Device.Wireless",
                                           "org.freedesktop.NetworkManager.AccessPoint",
                                           "org.freedesktop.NetworkManager.IP4Config",
                                           "org.freedesktop.NetworkManager.IP6Config" };
        }

        protected override void apply_snapshot (Variant ?objects) {
            var sample = WirelessData.NetworkSample.parse (objects);
            if (information) {
                apply_information_sample (sample);
                return;
            }
            network_label.label = sample.kind;
            network_name.label = sample.state == "Connected" ? sample.name : sample.state;
            string tooltip = network_name.label;
            if (sample.interface_name != "") {
                tooltip += " · " + sample.interface_name;
            }
            if (sample.address != "" && sample.address != network_name.label) {
                tooltip += " · " + sample.address;
            }
            network_name.tooltip_text = tooltip;
            strength.label = SystemData.percentage (sample.strength);
            signal_row.visible = sample.kind == "WIFI";
            visible = sample.present;
            debug ("network sample: %s %s", sample.kind, network_name.label);
        }

        void apply_information_sample (WirelessData.NetworkSample sample) {
            network_name.label = sample.state == "Connected"
                ? sample.kind == "ETH" ? "Ethernet"
                    : sample.kind == "WIFI" ? sample.name : "Network"
                : sample.state;
            string icon_name = sample.kind == "ETH" ? "network-wired-symbolic"
                : sample.kind == "WIFI" ? "network-wireless-symbolic"
                : "network-transmit-receive-symbolic";
            string fallback = sample.kind == "ETH" ? "network-wired"
                : sample.kind == "WIFI" ? "network-wireless"
                : "network-transmit-receive";
            if (sample.kind == "WIFI" && sample.strength >= 0) {
                string level = sample.strength >= 80 ? "excellent" : sample.strength >= 55 ? "good"
                    : sample.strength >= 30 ? "ok" : sample.strength > 0 ? "weak" : "none";
                icon_name = "network-wireless-signal-%s-symbolic".printf (level);
                fallback = "network-wireless-signal-%s".printf (level);
            }
            if (information_icon != null) {
                information_left.remove (information_icon);
            }
            information_icon = InformationIcons.symbol (icon_name, fallback,
                                                        sample.kind == "ETH" ? "Ethernet"
                                                          : sample.kind == "WIFI" ? "Wi-Fi"
                                                          : "Network");
            information_left.prepend (information_icon);
            if (sample.kind == "WIFI") {
                information_detail_label.label = "Signal";
                strength.label = SystemData.percentage (sample.strength);
                network_name.tooltip_text = sample.name;
                strength.tooltip_text = sample.strength >= 0
                    ? "Wi-Fi signal: %s".printf (SystemData.percentage (sample.strength))
                    : "Wi-Fi signal unavailable";
                information_icon.add_css_class (sample.strength >= 0
                                                ? "information-wifi-signal-known"
                                                : "information-wifi-signal-unknown");
            } else {
                information_detail_label.label = "IP";
                strength.label = sample.address != "" ? sample.address : "—";
                network_name.tooltip_text = sample.kind == "ETH" ? "Ethernet" : sample.state;
                strength.tooltip_text = sample.address != ""
                    ? sample.address : "IP address unavailable";
            }
            activity.select_interface (sample.state == "Connected" ? sample.interface_name : "");
            if (sample.interface_name != "") {
                network_name.tooltip_text += " · " + sample.interface_name;
            }
            if (sample.address != "") {
                network_name.tooltip_text += " · " + sample.address;
            }
            visible = sample.present;
            debug ("network information sample: %s %s · %s",
                   sample.kind, network_name.label, sample.address);
        }
    }

    public class Bluetooth : BusWidget {
        public override string widget_name { get {
                                                 return "bluetooth";
                                             } }
        Gtk.Grid devices = new Gtk.Grid ();
        Gtk.Button more = new Gtk.Button ();
        WirelessData.BluetoothSample ?sample;
        bool expanded = false;
        bool information;

        public Bluetooth (string suffix, bool information = false) {
            base (suffix, "org.bluez", "/");
            this.information = information;
            if (information) {
                orientation = Gtk.Orientation.VERTICAL;
                spacing = 8;
            } else {
                add_heading ("Bluetooth");
            }
            devices.column_homogeneous = true;
            devices.column_spacing = 20;
            devices.row_spacing = 8;
            devices.hexpand = true;
            if (information) {
                devices.add_css_class ("information-device-grid");
            }
            append (devices);
            more.add_css_class ("flat");
            more.add_css_class ("bluetooth-more");
            if (information) {
                more.add_css_class ("information-more");
            }
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
            visible = sample.devices.length > 0;
            debug ("bluetooth devices: %u; visible: %s", sample.devices.length,
                   visible.to_string ());
        }

        void rebuild () {
            if (sample == null) {
                return;
            }
            Gtk.Widget ?child;
            while ((child = devices.get_first_child ()) != null) {
                devices.remove (child);
            }
            int count = (int) sample.devices.length;
            int shown = expanded ? count : int.min (count, 2);
            for (int i = 0; i < shown; i++) {
                var entry = sample.devices[i];
                var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, information ? 6 : 8);
                if (information) {
                    row.add_css_class ("information-device");
                    row.append (InformationIcons.bluetooth (entry.icon));
                }
                var label = new Gtk.Label (entry.name);
                label.xalign = 0;
                label.hexpand = true;
                label.max_width_chars = 1;
                label.ellipsize = Pango.EllipsizeMode.END;
                label.single_line_mode = true;
                label.tooltip_text = entry.name;
                label.add_css_class (information ? "information-device-name" : "metric-label");
                row.append (label);
                var percentage = new Gtk.Label (SystemData.percentage (entry.battery));
                percentage.xalign = 1;
                percentage.single_line_mode = true;
                percentage.add_css_class ("metric-value");
                percentage.tooltip_text = entry.battery >= 0 ? "Battery" : "Battery not reported";
                if (information) {
                    percentage.add_css_class ("information-device-value");
                    percentage.update_property (Gtk.AccessibleProperty.LABEL,
                                                entry.battery >= 0
                                                ? "Battery: %s".printf (SystemData.percentage (
                                                                            entry.battery))
                                                : "Battery not reported", -1);
                }
                row.append (percentage);
                devices.attach (row, i % 2, i / 2);
            }
            if (shown % 2 != 0) {
                devices.attach (new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0), 1, shown / 2);
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

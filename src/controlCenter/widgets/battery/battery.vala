namespace SwayNotificationCenter.Widgets {
    public class Battery : PollingWidget {
        public override string widget_name { get {
                                                 return "battery";
                                             } }

        SystemData.Reader reader = new SystemData.Reader ();
        Gtk.Box container = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
        Gee.ArrayList<BatteryRow> rows = new Gee.ArrayList<BatteryRow> ();
        bool compact;

        class BatteryRow : Gtk.Grid {
            public string supply_name;
            Gtk.Label status;
            Gtk.Label power;
            Gtk.Label eta;
            Gtk.Label ?charge;

            public BatteryRow (string name, bool multiple, bool compact) {
                this.supply_name = name;
                column_spacing = compact ? 6 : 16;
                row_spacing = 8;
                hexpand = true;
                Gtk.Grid state_grid = this;
                Gtk.Grid power_grid = this;
                if (compact) {
                    column_homogeneous = true;
                    column_spacing = 20;
                    state_grid = new Gtk.Grid ();
                    power_grid = new Gtk.Grid ();
                    foreach (var grid in new Gtk.Grid[] { state_grid, power_grid }) {
                        grid.column_spacing = 6;
                        grid.row_spacing = 8;
                        grid.hexpand = true;
                    }
                    attach (state_grid, 0, 0);
                    attach (power_grid, 1, 0);
                }
                status = add_metric (state_grid, 0,
                                     compact ? (multiple ? name : "State") :
                                     (multiple ? "BAT %s".printf (name) : "BAT"));
                if (compact) {
                    charge = add_metric (state_grid, 1, "Charge");
                }
                power = add_metric (power_grid, compact ? 0 : 1, "PWR");
                eta = add_metric (power_grid, compact ? 1 : 2, "ETA");
                power.tooltip_text = "Battery charge/discharge power";
                eta.tooltip_text = "Approximate time at the current battery rate";
            }

            public void update (SystemData.BatterySample sample) {
                string percentage = sample.percentage >= 0
                    ? "%.0f%%".printf (sample.percentage) : "—";
                status.label = "%s · %s".printf (sample.state, percentage);
                if (charge != null) {
                    status.label = sample.state;
                    charge.label = percentage;
                }
                power.label = sample.power >= 0 ? "%.1f W".printf (sample.power / 1000000) : "—";
                eta.label = sample.eta ();
                status.tooltip_text = sample.state;
                eta.tooltip_text = "Approximate time at the current battery rate: " + sample.eta ();
                debug ("battery sample: %s %s; PWR %s; ETA %s",
                       supply_name, status.label, power.label, eta.label);
            }
        }

        public Battery (string suffix, bool compact = false) {
            base (suffix);
            this.compact = compact;
            if (compact) {
                add_heading ("Battery");
            }
            configure_interval (5);
            container.hexpand = true;
            append (container);
            visible = false;
        }

        protected override async void update_sample (Cancellable cancellable) {
            var samples = yield reader.batteries (cancellable);

            if (cancellable.is_cancelled ()) {
                return;
            }
            bool rebuild = rows.size != samples.length;
            if (!rebuild) {
                for (int i = 0; i < rows.size; i++) {
                    if (rows[i].supply_name != samples[i].name) {
                        rebuild = true;
                        break;
                    }
                }
            }
            if (rebuild) {
                Gtk.Widget ?child;
                while ((child = container.get_first_child ()) != null) {
                    container.remove (child);
                }
                rows.clear ();
                foreach (var sample in samples) {
                    var row = new BatteryRow (sample.name, samples.length > 1, compact);
                    rows.add (row);
                    container.append (row);
                }
            }
            for (int i = 0; i < rows.size; i++) {
                rows[i].update (samples[i]);
            }
            visible = samples.length > 0;
            debug ("battery snapshot: %d system batteries", samples.length);
        }
    }
}

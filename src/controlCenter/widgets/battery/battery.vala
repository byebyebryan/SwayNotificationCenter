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
            Gtk.Box ?rate_row;

            public BatteryRow (string name, bool multiple, bool compact) {
                this.supply_name = name;
                column_spacing = compact ? 6 : 16;
                row_spacing = 8;
                hexpand = true;
                if (compact) {
                    column_homogeneous = true;
                    column_spacing = 20;
                    var charge_grid = new Gtk.Grid ();
                    var state_grid = new Gtk.Grid ();
                    var power_grid = new Gtk.Grid ();
                    var eta_grid = new Gtk.Grid ();
                    foreach (var grid in new Gtk.Grid[] { charge_grid, state_grid,
                                                          power_grid, eta_grid }) {
                        grid.column_spacing = 6;
                        grid.hexpand = true;
                    }
                    charge = add_metric (charge_grid, 0,
                                         multiple ? "Charge %s".printf (name) : "Charge");
                    status = add_metric (state_grid, 0, "State");
                    power = add_metric (power_grid, 0, "PWR");
                    eta = add_metric (eta_grid, 0, "ETA");
                    attach (charge_grid, 0, 0);
                    attach (state_grid, 1, 0);
                    rate_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 20);
                    rate_row.homogeneous = true;
                    rate_row.hexpand = true;
                    rate_row.append (power_grid);
                    rate_row.append (eta_grid);
                    attach (rate_row, 0, 1, 2);
                } else {
                    status = add_metric (this, 0, multiple ? "BAT %s".printf (name) : "BAT");
                    power = add_metric (this, 1, "PWR");
                    eta = add_metric (this, 2, "ETA");
                }
                power.tooltip_text = "Battery charge/discharge power";
                eta.tooltip_text = "Approximate time at the current battery rate";
            }

            public void update (SystemData.BatterySample sample) {
                string percentage = SystemData.percentage (sample.percentage);
                status.label = "%s · %s".printf (sample.display_state (), percentage);
                if (charge != null) {
                    status.label = sample.display_state ();
                    charge.label = percentage;
                }
                power.label = sample.power >= 0 ? "%.1f W".printf (sample.power / 1000000) : "—";
                eta.label = sample.eta ();
                if (rate_row != null) {
                    rate_row.visible = !sample.resting_on_external_power ();
                }
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

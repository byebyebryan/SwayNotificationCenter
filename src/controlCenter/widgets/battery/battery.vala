namespace SwayNotificationCenter.Widgets {
    public class Battery : PollingWidget {
        public override string widget_name { get {
                                                 return "battery";
                                             } }

        SystemData.Reader reader = new SystemData.Reader ();
        Gtk.Box container = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
        Gee.ArrayList<BatteryRow> rows = new Gee.ArrayList<BatteryRow> ();
        bool compact;
        bool information;

        class BatteryRow : Gtk.Grid {
            public string supply_name;
            Gtk.Label status;
            Gtk.Label power;
            Gtk.Label eta;
            Gtk.Label ?charge;
            Gtk.Box ?rate_row;
            InformationMeter ?information_meter;

            public BatteryRow (string name, bool multiple, bool compact, bool information) {
                this.supply_name = name;
                if (information) {
                    column_spacing = 20;
                    row_spacing = 8;
                    hexpand = true;
                    information_meter = new InformationMeter (name, "battery-full-symbolic");
                    information_meter.hexpand = true;
                    information_meter.add_css_class ("information-battery-meter");
                    attach (information_meter, 0, 0, 2, 1);

                    status = new Gtk.Label ("");
                    status.xalign = 1;
                    status.ellipsize = Pango.EllipsizeMode.END;
                    status.single_line_mode = true;
                    status.max_width_chars = 1;
                    status.add_css_class ("information-battery-state");
                    information_meter.set_battery_header (multiple ? name + " ·" : "", status);

                    var rate_row_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 20);
                    rate_row_box.homogeneous = true;
                    rate_row_box.hexpand = true;
                    var power_grid = new Gtk.Grid ();
                    var eta_grid = new Gtk.Grid ();
                    power_grid.column_spacing = eta_grid.column_spacing = 6;
                    power_grid.hexpand = eta_grid.hexpand = true;
                    power = add_metric (power_grid, 0, "PWR");
                    eta = add_metric (eta_grid, 0, "ETA");
                    rate_row_box.append (power_grid);
                    rate_row_box.append (eta_grid);
                    rate_row_box.add_css_class ("information-battery-rates");
                    rate_row = rate_row_box;
                    attach (rate_row, 0, 1, 2, 1);
                    power.tooltip_text = "Battery charge/discharge power";
                    eta.tooltip_text = "Approximate time at the current battery rate";
                    return;
                }
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
                if (information_meter != null) {
                    bool low = sample.state == "Discharging" && sample.percentage >= 0
                        && sample.percentage <= 20;
                    bool critical = low && sample.percentage <= 10;
                    string state = sample.display_state ();
                    if (low) {
                        state = "Low · Discharging";
                    }
                    status.label = state;
                    status.tooltip_text = sample.state;
                    status.remove_css_class ("information-battery-warning");
                    status.remove_css_class ("information-battery-critical");
                    if (low) {
                        status.add_css_class (critical ? "information-battery-critical"
                                               : "information-battery-warning");
                    }
                    information_meter.set_reading (sample.percentage);
                    information_meter.tooltip_text = "%s · %s · %s".printf (
                        supply_name, SystemData.percentage (sample.percentage), state);
                    information_meter.set_tone (sample.state == "Charging" ? "charging"
                                                : critical ? "critical"
                                                : low ? "warning" : "");
                    information_meter.set_accessibility_description (
                        critical ? "Low battery. Discharging." : state);
                    information_meter.set_reported_limit (sample.limit);
                    power.label = sample.power >= 0
                        ? "%.1f W".printf (sample.power / 1000000) : "—";
                    eta.label = sample.eta ();
                    rate_row.visible = !sample.resting_on_external_power ();
                    return;
                }
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

        public Battery (string suffix, bool compact = false, bool information = false) {
            base (suffix);
            this.compact = compact;
            this.information = information;
            if (compact && !information) {
                add_heading ("Battery");
            }
            configure_interval (5);
            if (information) {
                container.spacing = 10;
            }
            container.hexpand = true;
            append (container);
            visible = false;
        }

        protected override void reset_sample () {
            visible = false;
        }

        protected override async void update_sample (Cancellable cancellable) {
            var samples = yield reader.batteries (cancellable);

            if (cancellable.is_cancelled ()) {
                return;
            }
            apply_batteries (samples);
        }

        internal void apply_batteries (SystemData.BatterySample[] samples) {
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
                    var row = new BatteryRow (sample.name, samples.length > 1, compact,
                                              information);
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

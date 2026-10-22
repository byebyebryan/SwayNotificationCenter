namespace SwayNotificationCenter.Widgets {
    public class SystemStats : PollingWidget {
        public override string widget_name { get {
                                                 return "system-stats";
                                             } }

        SystemData.Reader reader = new SystemData.Reader ();
        SystemData.CpuTimes ?previous = null;
        Gtk.Label cpu_value;
        Gtk.Label memory_value;
        bool compact;
        GpuStats ?gpu;

        public SystemStats (string suffix, bool compact = false) {
            base (suffix);
            this.compact = compact;
            if (compact) {
                add_heading ("System");
            }
            configure_interval (1);
            var grid = new Gtk.Grid ();
            grid.column_spacing = compact ? 6 : 16;
            grid.row_spacing = 8;
            grid.hexpand = true;
            cpu_value = add_metric (grid, 0, "CPU");
            memory_value = add_metric (grid, 1, "RAM");
            if (compact) {
                var columns = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 20);
                columns.homogeneous = true;
                columns.hexpand = true;
                grid.valign = Gtk.Align.START;
                gpu = new GpuStats (suffix);
                gpu.hexpand = true;
                gpu.valign = Gtk.Align.START;
                columns.append (grid);
                columns.append (gpu);
                append (columns);
            } else {
                append (grid);
            }
        }

        protected override void reset_sample () {
            previous = null;
            cpu_value.label = "—";
        }

        protected override async void update_sample (Cancellable cancellable) {
            var sample = yield reader.system (cancellable);

            if (cancellable.is_cancelled ()) {
                return;
            }
            double usage = sample.cpu != null ?sample.cpu.usage_since (previous) : -1;

            previous = sample.cpu;
            string frequency = sample.frequency_ghz > 0
                ? "%.1f GHz".printf (sample.frequency_ghz) : "—";
            string utilization = usage >= 0 ? "%.0f%%".printf (usage) : "—";
            cpu_value.label = "%s · %s".printf (frequency, utilization);
            if (sample.memory_total_gib > 0) {
                memory_value.label = "%.1f / %.1f GiB · %.0f%%".printf (
                    sample.memory_used_gib, sample.memory_total_gib,
                    100 * sample.memory_used_gib / sample.memory_total_gib);
                memory_value.tooltip_text = memory_value.label;
                if (compact) {
                    memory_value.label = "%.1f GiB · %.0f%%".printf (sample.memory_used_gib,
                                                                     100 * sample.memory_used_gib /
                                                                     sample.memory_total_gib);
                }
            } else {
                memory_value.label = "—";
            }
            debug ("system-stats sample: CPU %s; RAM %s", cpu_value.label, memory_value.label);
        }

        public override void on_cc_visibility_change (bool visible) {
            base.on_cc_visibility_change (visible);
            if (gpu != null) {
                gpu.on_cc_visibility_change (visible);
            }
        }
    }
}

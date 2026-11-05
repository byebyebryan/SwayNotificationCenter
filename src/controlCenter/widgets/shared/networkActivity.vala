namespace SwayNotificationCenter.Widgets {
    /** The information panel's rates, sampled only for its displayed primary link. */
    public class NetworkActivity : PollingWidget {
        public override string widget_name { get {
                                                 return "network-activity";
                                             } }

        NetworkData.Reader reader = new NetworkData.Reader ();
        NetworkData.Tracker tracker = new NetworkData.Tracker ();
        Gtk.Label upload;
        Gtk.Label download;
        string interface_name = "";
        bool panel_open = false;

        public NetworkActivity (string suffix) {
            base (suffix);
            orientation = Gtk.Orientation.VERTICAL;
            valign = Gtk.Align.START;
            hexpand = true;
            add_css_class ("information-network-activity");
            var grid = new Gtk.Grid ();
            grid.column_spacing = 6;
            grid.row_spacing = 4;
            grid.hexpand = true;
            upload = add_metric (grid, 0, "↑ Up");
            download = add_metric (grid, 1, "↓ Down");
            upload.add_css_class ("information-connection-value");
            upload.add_css_class ("information-upload-value");
            download.add_css_class ("information-connection-value");
            download.add_css_class ("information-download-value");
            append (grid);
            reset_sample ();
        }

        public void select_interface (string selected) {
            if (selected == interface_name) {
                return;
            }
            interface_name = selected;
            reset_sample ();
            // Retire the old interface's in-flight read before taking a new baseline.
            base.on_cc_visibility_change (panel_open && selected != "");
        }

        protected virtual async NetworkData.Counters ?read_counters (
            string selected, Cancellable cancellable) {
            return yield reader.counters (selected, cancellable);
        }

        protected virtual int64 sample_time () {
            return get_monotonic_time ();
        }

        protected override void reset_sample () {
            tracker.reset ();
            apply_rates (new NetworkData.RateSample ());
        }

        protected override async void update_sample (Cancellable cancellable) {
            string selected = interface_name;
            var counters = yield read_counters (selected, cancellable);

            if (cancellable.is_cancelled ()) {
                return;
            }
            var sample = tracker.sample (selected, counters, sample_time ());
            apply_rates (sample);
            debug ("network activity sample: %s; up %s; down %s",
                   selected, upload.label, download.label);
        }

        internal void apply_rates (NetworkData.RateSample sample) {
            upload.label = NetworkData.rate (sample.upload);
            download.label = NetworkData.rate (sample.download);
            upload.tooltip_text = "Upload: " + upload.label;
            download.tooltip_text = "Download: " + download.label;
            upload.update_property (Gtk.AccessibleProperty.LABEL, "Upload transfer rate",
                                    Gtk.AccessibleProperty.DESCRIPTION, upload.label, -1);
            download.update_property (Gtk.AccessibleProperty.LABEL, "Download transfer rate",
                                      Gtk.AccessibleProperty.DESCRIPTION, download.label, -1);
        }

        public override void on_cc_visibility_change (bool visible) {
            panel_open = visible;
            base.on_cc_visibility_change (visible && interface_name != "");
        }

        public override void unroot () {
            panel_open = false;
            base.unroot ();
        }
    }
}

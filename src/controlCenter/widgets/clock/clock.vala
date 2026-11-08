namespace SwayNotificationCenter.Widgets {
    public class Clock : BaseWidget {
        public override string widget_name {
            get {
                return "clock";
            }
        }

        Gtk.Label time_label;
        Gtk.Label date_label;
        string time_format = "%H:%M";
        string date_format = "%a, %b %-d";
        uint timer_id = 0;

        public Clock (string suffix) {
            base (suffix);

            Json.Object ?config = get_config (this);
            if (config != null) {
                string ?configured_time_format = get_prop<string> (config, "time-format");
                if (configured_time_format != null) {
                    time_format = configured_time_format;
                }

                string ?configured_date_format = get_prop<string> (config, "date-format");
                if (configured_date_format != null) {
                    date_format = configured_date_format;
                }
            }

            orientation = Gtk.Orientation.HORIZONTAL;
            homogeneous = true;
            spacing = 20;

            time_label = new Gtk.Label (null);
            time_label.add_css_class ("clock-time");
            time_label.add_css_class ("metric-value");
            time_label.set_hexpand (true);
            time_label.set_xalign (0.0f);
            time_label.set_ellipsize (Pango.EllipsizeMode.END);
            time_label.set_single_line_mode (true);
            time_label.set_max_width_chars (1);

            date_label = new Gtk.Label (null);
            date_label.add_css_class ("clock-date");
            date_label.add_css_class ("metric-value");
            date_label.set_hexpand (true);
            date_label.set_xalign (0.0f);
            date_label.set_ellipsize (Pango.EllipsizeMode.END);
            date_label.set_single_line_mode (true);
            date_label.set_max_width_chars (1);

            append (time_label);
            append (date_label);
        }

        // Protected so the private widget harness can supply deterministic times.
        protected virtual DateTime get_current_time () {
            return new DateTime.now_local ();
        }

        void update_labels () {
            DateTime now = get_current_time ();
            time_label.set_label (now.format (time_format) ?? "");
            date_label.set_label (now.format (date_format) ?? "");
            date_label.set_tooltip_text (now.format ("%A, %B %-d, %Y"));
        }

        void stop_timer () {
            if (timer_id != 0) {
                Source.remove (timer_id);
                timer_id = 0;
            }
        }

        public override void on_cc_visibility_change (bool visible) {
            stop_timer ();
            if (!visible) {
                return;
            }

            // Refresh before the panel is shown, then sample once per second so
            // wall-clock changes and date rollovers appear promptly.
            update_labels ();
            timer_id = Timeout.add (1000, () => {
                update_labels ();
                return Source.CONTINUE;
            });
        }

        public override void unroot () {
            stop_timer ();
            base.unroot ();
        }
    }
}

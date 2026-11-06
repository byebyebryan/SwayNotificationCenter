namespace SwayNotificationCenter.Widgets {
    internal class InformationIcons {
        static bool has_icon (string name) {
            Gdk.Display ?display = Gdk.Display.get_default ();
            if (display == null) {
                return false;
            }
            return Gtk.IconTheme.get_for_display (display).has_icon (name);
        }

        static string ?available (string name) {
            if (name == "") {
                return null;
            }
            if (!name.has_suffix ("-symbolic") && has_icon (name + "-symbolic")) {
                return name + "-symbolic";
            }
            return has_icon (name) ? name : null;
        }

        public static Gtk.Widget symbol (string preferred, string fallback,
                                         string label, string fallback_text = "⌁") {
            string ?name = available (preferred);
            if (name == null) {
                name = available (fallback);
            }
            if (name != null) {
                var image = new Gtk.Image ();
                image.set_from_icon_name (name);
                image.set_pixel_size (16);
                image.add_css_class ("information-symbol");
                image.set_tooltip_text (label);
                image.update_property (Gtk.AccessibleProperty.LABEL, label, -1);
                return image;
            }
            var glyph = new Gtk.Label (fallback_text);
            glyph.add_css_class ("information-symbol");
            glyph.set_tooltip_text (label);
            glyph.update_property (Gtk.AccessibleProperty.LABEL, label, -1);
            return glyph;
        }

        public static Gtk.Widget bluetooth (string metadata_icon) {
            return symbol (metadata_icon, "bluetooth-symbolic", "Bluetooth device", "ᛒ");
        }
    }

    /** A typed, accessible 0–100 meter shared by the Information sections. */
    internal class InformationMeter : Gtk.Box {
        Gtk.Label name_label;
        Gtk.Label value_label;
        Gtk.Label unavailable_label;
        Gtk.Label detail_label;
        Gtk.Box heading_left;
        Gtk.Box heading_right;
        Gtk.Box heading;
        Gtk.Widget ?heading_icon = null;
        Gtk.LevelBar level;
        Gtk.Overlay track;
        Gtk.DrawingArea ?limit_marker;
        string metric_name;
        string accessibility_description = "";

        public InformationMeter (string name, string icon = "") {
            Object (orientation : Gtk.Orientation.VERTICAL, spacing : 6);
            metric_name = name;
            add_css_class ("information-meter");

            heading = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            heading.add_css_class ("information-meter-heading");
            heading_left = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            heading_left.hexpand = true;
            heading_left.add_css_class ("information-meter-name-group");
            if (icon != "") {
                heading_icon = InformationIcons.symbol (icon, "battery-full-symbolic",
                                                        name, "▰");
                heading_left.append (heading_icon);
            }
            name_label = new Gtk.Label (name);
            name_label.xalign = 0;
            name_label.hexpand = true;
            name_label.set_single_line_mode (true);
            name_label.ellipsize = Pango.EllipsizeMode.END;
            name_label.add_css_class ("information-meter-label");
            heading_left.append (name_label);
            value_label = new Gtk.Label ("—");
            value_label.xalign = 1;
            value_label.set_single_line_mode (true);
            value_label.ellipsize = Pango.EllipsizeMode.END;
            value_label.add_css_class ("information-meter-value");
            heading_right = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            heading_right.halign = Gtk.Align.END;
            heading_right.append (value_label);
            heading.append (heading_left);
            heading.append (heading_right);
            append (heading);

            track = new Gtk.Overlay ();
            track.add_css_class ("information-meter-track");
            level = new Gtk.LevelBar.for_interval (0, 100);
            level.set_hexpand (true);
            level.set_min_value (0);
            level.set_max_value (100);
            level.add_css_class ("information-meter-level");
            level.update_property (Gtk.AccessibleProperty.LABEL,
                                   "%s utilization".printf (name), -1);
            track.set_child (level);
            append (track);

            unavailable_label = new Gtk.Label ("Unavailable");
            unavailable_label.xalign = 0;
            unavailable_label.add_css_class ("information-meter-unavailable");
            append (unavailable_label);

            detail_label = new Gtk.Label ("");
            detail_label.xalign = 0;
            detail_label.ellipsize = Pango.EllipsizeMode.END;
            detail_label.add_css_class ("information-meter-detail");
            append (detail_label);

            set_reading (-1, "");
        }

        public void set_battery_header (string identity, Gtk.Widget state) {
            heading.homogeneous = true;
            heading.spacing = 20;
            heading_right.halign = Gtk.Align.FILL;
            heading_right.hexpand = true;
            state.hexpand = true;
            Gtk.Widget ?child;
            while ((child = heading_left.get_first_child ()) != null) {
                heading_left.remove (child);
            }
            while ((child = heading_right.get_first_child ()) != null) {
                heading_right.remove (child);
            }
            if (heading_icon != null) {
                heading_left.append (heading_icon);
            }
            name_label.set_text (identity);
            name_label.visible = identity != "";
            name_label.tooltip_text = identity != "" ? identity.strip () : null;
            if (identity != "") {
                heading_left.append (name_label);
            }
            heading_left.append (value_label);
            heading_right.append (state);
        }

        public void set_reading (double percentage, string detail = "") {
            bool known = percentage.is_finite () && percentage >= 0 && percentage <= 100;
            if (known) {
                // The displayed integer and the level bar always describe the same value.
                double rounded = double.max (0, double.min (100, Math.round (percentage)));
                string text = SystemData.percentage (rounded);
                value_label.set_text (text);
                value_label.tooltip_text = "%s: %s".printf (metric_name, text);
                level.set_value (rounded);
                level.set_tooltip_text ("%s: %s".printf (metric_name, text));
                level.update_property (Gtk.AccessibleProperty.LABEL,
                                       "%s: %s".printf (metric_name, text), -1);
                level.update_property (Gtk.AccessibleProperty.DESCRIPTION,
                                       accessibility_description, -1);
                level.visible = true;
                unavailable_label.visible = false;
            } else {
                value_label.set_text ("—");
                value_label.tooltip_text = "%s unavailable".printf (metric_name);
                level.set_tooltip_text ("%s unavailable".printf (metric_name));
                level.update_property (Gtk.AccessibleProperty.LABEL,
                                       "%s unavailable".printf (metric_name), -1);
                level.update_property (Gtk.AccessibleProperty.DESCRIPTION,
                                       accessibility_description, -1);
                level.visible = false;
                unavailable_label.visible = true;
            }
            detail_label.set_text (detail);
            detail_label.visible = detail != "";
        }

        public void set_tone (string tone) {
            foreach (string css in new string[] { "information-meter-charging",
                                                  "information-meter-warning",
                                                  "information-meter-critical" }) {
                remove_css_class (css);
            }
            if (tone in new string[] { "charging", "warning", "critical" }) {
                add_css_class ("information-meter-" + tone);
            }
        }

        public void set_accessibility_description (string description) {
            accessibility_description = description;
            if (level.visible) {
                level.update_property (Gtk.AccessibleProperty.DESCRIPTION,
                                       accessibility_description, -1);
            }
        }

        internal string get_reading_text () {
            return value_label.get_text ();
        }

        static void draw_limit (Gtk.DrawingArea area, Cairo.Context context,
                                int width, int height) {
            unowned Variant ?reading = area.get_data<Variant> ("reported-limit");
            if (reading == null || width <= 0) {
                return;
            }
            Gdk.RGBA color = area.get_color ();
            context.set_source_rgba (color.red, color.green, color.blue, 0.8);
            context.set_line_width (1);
            double x = Math.round (width * reading.get_double () / 100.0) + 0.5;
            context.move_to (double.min (width - 1, x), 0);
            context.line_to (double.min (width - 1, x), height);
            context.stroke ();
        }

        public void set_reported_limit (double limit) {
            bool valid = limit.is_finite () && limit > 0 && limit <= 100;
            if (!valid) {
                if (limit_marker != null) {
                    track.remove_overlay (limit_marker);
                    limit_marker = null;
                }
                level.update_property (Gtk.AccessibleProperty.DESCRIPTION,
                                       accessibility_description, -1);
                return;
            }
            if (limit_marker == null) {
                limit_marker = new Gtk.DrawingArea ();
                limit_marker.hexpand = true;
                limit_marker.vexpand = true;
                limit_marker.halign = Gtk.Align.FILL;
                limit_marker.valign = Gtk.Align.FILL;
                limit_marker.set_can_target (false);
                limit_marker.add_css_class ("information-limit-marker");
                // A static callback keeps the marker from retaining its owning meter.
                limit_marker.set_draw_func (draw_limit);
                track.add_overlay (limit_marker);
            }
            limit_marker.set_data<Variant> ("reported-limit", new Variant.double (limit));
            string description = accessibility_description != ""
                ? accessibility_description + ". " : "";
            level.update_property (Gtk.AccessibleProperty.DESCRIPTION,
                                   description + "Reported charge limit: %.0f%%".printf (limit),
                                   -1);
            level.set_tooltip_text ("Reported charge limit: %.0f%%".printf (limit));
            limit_marker.queue_draw ();
        }
    }
}

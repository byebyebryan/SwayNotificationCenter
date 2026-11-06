namespace SwayNotificationCenter.Widgets {
    public class Title : BaseWidget {
        public override string widget_name {
            get {
                return "title";
            }
        }

        Gtk.Label title_widget;
        Gtk.Button clear_all_button;

        // Default config values
        string title = "Notifications";
        bool has_clear_all_button = true;
        bool show_dnd = false;
        string button_text = "Clear All";

        public Title (string suffix) {
            base (suffix);

            Json.Object ?config = get_config (this);
            if (config != null) {
                // Get title
                string ?title = get_prop<string> (config, "text");
                if (title != null) {
                    this.title = title;
                }
                // Get has clear-all-button
                bool found_clear_all;
                bool ?has_clear_all_button = get_prop<bool> (
                    config, "clear-all-button", out found_clear_all);
                if (found_clear_all) {
                    this.has_clear_all_button = has_clear_all_button;
                }
                // Get whether to place Do Not Disturb alongside the title
                bool found_show_dnd;
                bool ?show_dnd = get_prop<bool> (config, "show-dnd", out found_show_dnd);
                if (found_show_dnd) {
                    this.show_dnd = show_dnd;
                }
                // Get button text
                string ?button_text = get_prop<string> (config, "button-text");
                if (button_text != null) {
                    this.button_text = button_text;
                }
            }

            title_widget = new Gtk.Label (title);
            title_widget.set_hexpand (true);
            title_widget.set_halign (Gtk.Align.START);
            append (title_widget);

            if (show_dnd) {
                var dnd_group = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
                dnd_group.add_css_class ("title-inline-dnd");

                var dnd_label = new Gtk.Label ("DND");
                dnd_label.set_tooltip_text ("Do Not Disturb");

                var dnd_switch = new Gtk.Switch ();
                dnd_switch.set_tooltip_text ("Do Not Disturb");
                dnd_switch.update_property (
                    Gtk.AccessibleProperty.LABEL, "Do Not Disturb", -1);
                dnd_switch.valign = Gtk.Align.CENTER;
                noti_daemon.bind_property (
                    "dnd",
                    dnd_switch,
                    "active",
                    BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);

                dnd_group.append (dnd_label);
                dnd_group.append (dnd_switch);
                append (dnd_group);
            }

            if (has_clear_all_button) {
                clear_all_button = new Gtk.Button.with_label (button_text);
                clear_all_button.clicked.connect (() => {
                    noti_daemon.request_dismiss_all_notifications (ClosedReasons.DISMISSED);
                });
                clear_all_button.set_sensitive (!notifications_widget.is_empty ());

                swaync_daemon.subscribe_v2.connect ((count) => {
                    clear_all_button.set_sensitive (count > 0);
                });
                clear_all_button.set_can_focus (false);
                clear_all_button.valign = Gtk.Align.CENTER;
                // Backwards compatible towards older CSS stylesheets
                clear_all_button.add_css_class ("control-center-clear-all");
                append (clear_all_button);
            }
        }
    }
}

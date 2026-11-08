namespace SwayNotificationCenter.Widgets {
    public class Information : BaseWidget {
        public override string widget_name {
            get {
                return "information";
            }
        }

        Clock clock;
        SystemStats system;
        Network network;
        Bluetooth bluetooth;
        Battery battery;
        Gtk.Box system_section;
        Gtk.Box connections_section;
        Gtk.Box battery_section;
        Gtk.Box divider_after_clock;
        Gtk.Box divider_after_system;
        Gtk.Box divider_after_connections;

        public Information (string suffix) {
            base (suffix);
            initialize (new Clock (suffix),
                        new SystemStats (suffix, true, true),
                        new Network (suffix, true), new Bluetooth (suffix, true),
                        new Battery (suffix, true, true));
        }

        // The private native widget harness injects typed fixtures at the same
        // presentation boundary used by the live readers.
        internal Information.with_widgets (string suffix, Clock clock, SystemStats system,
                                           Network network, Bluetooth bluetooth,
                                           Battery battery) {
            base (suffix);
            initialize (clock, system, network, bluetooth, battery);
        }

        void initialize (Clock clock, SystemStats system,
                         Network network, Bluetooth bluetooth, Battery battery) {
            this.clock = clock;
            this.system = system;
            this.network = network;
            this.bluetooth = bluetooth;
            this.battery = battery;
            orientation = Gtk.Orientation.VERTICAL;
            spacing = 0;
            hexpand = true;

            clock.add_css_class ("information-clock");
            append (clock);
            divider_after_clock = divider ();
            append (divider_after_clock);

            system_section = section ("System", system);
            append (system_section);
            divider_after_system = divider ();
            append (divider_after_system);

            var connections = new Gtk.Box (Gtk.Orientation.VERTICAL, 10);
            connections.hexpand = true;
            connections.add_css_class ("information-connections-content");
            connections.append (network);
            connections.append (bluetooth);
            connections_section = section ("Connections", connections);
            append (connections_section);
            divider_after_connections = divider ();
            append (divider_after_connections);

            battery_section = section ("Battery", battery);
            append (battery_section);

            network.notify["visible"].connect (update_sections);
            bluetooth.notify["visible"].connect (update_sections);
            battery.notify["visible"].connect (update_sections);
            update_sections ();
        }

        Gtk.Box section (string title, Gtk.Widget content) {
            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 10);
            box.hexpand = true;
            box.add_css_class ("information-section");
            var heading = new Gtk.Label (title);
            heading.xalign = 0;
            heading.add_css_class ("information-section-title");
            box.append (heading);
            box.append (content);
            return box;
        }

        Gtk.Box divider () {
            var line = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            line.hexpand = true;
            line.set_size_request (-1, 1);
            line.add_css_class ("information-divider");
            return line;
        }

        void update_sections () {
            bool has_connections = network.visible || bluetooth.visible;
            bool has_battery = battery.visible;
            connections_section.visible = has_connections;
            battery_section.visible = has_battery;
            divider_after_system.visible = has_connections || has_battery;
            divider_after_connections.visible = has_connections && has_battery;
        }

        public override void on_cc_visibility_change (bool visible) {
            // Each reader is forwarded exactly once. SystemStats owns its GPU child.
            clock.on_cc_visibility_change (visible);
            system.on_cc_visibility_change (visible);
            network.on_cc_visibility_change (visible);
            bluetooth.on_cc_visibility_change (visible);
            battery.on_cc_visibility_change (visible);
        }
    }
}

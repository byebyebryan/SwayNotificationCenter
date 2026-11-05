using SwayNotificationCenter.Widgets;

namespace SwayNotificationCenter.WidgetTests {
    [CCode (cname = "gtk_test_accessible_check_property", cheader_filename = "gtk/gtk.h")]
    extern string ?gtk_test_accessible_check_property (Gtk.Accessible accessible,
                                                       Gtk.AccessibleProperty property,
                                                       ...);

    string test_config_path;
    Gtk.CssProvider ?fixture_css_provider = null;
    uint fixture_css_errors = 0;

    class NetworkFixture : Widgets.Network {
        public uint visibility_calls = 0;

        public NetworkFixture (bool information = false) {
            base ("", information);
        }

        public void seed (Variant ?snapshot) {
            apply_snapshot (snapshot);
        }

        public override void on_cc_visibility_change (bool visible) {
            visibility_calls++;
            if (visible) {
                apply_snapshot (null);
            } else {
                base.on_cc_visibility_change (false);
            }
        }
    }

    class BluetoothFixture : Widgets.Bluetooth {
        public uint visibility_calls = 0;

        public BluetoothFixture (bool information = false) {
            base ("", information);
        }

        public void seed (Variant snapshot) {
            apply_snapshot (snapshot);
        }

        public override void on_cc_visibility_change (bool visible) {
            visibility_calls++;
            if (visible) {
                apply_snapshot (null);
            } else {
                base.on_cc_visibility_change (false);
            }
        }
    }

    class ClockFixture : Widgets.Clock {
        public DateTime value;
        public uint reads = 0;
        public uint visibility_calls = 0;

        public ClockFixture (string suffix = "") {
            base (suffix);
        }

        protected override DateTime get_current_time () {
            reads++;
            return value;
        }

        public override void on_cc_visibility_change (bool visible) {
            visibility_calls++;
            base.on_cc_visibility_change (visible);
        }
    }

    class GpuFixture : Widgets.GpuStats {
        public uint visibility_calls = 0;

        public GpuFixture () {
            base ("", true);
        }

        protected override async void update_sample (Cancellable cancellable) {
        }

        public void seed (GpuData.Sample[] samples) {
            apply_samples (samples);
        }

        public override void on_cc_visibility_change (bool visible) {
            visibility_calls++;
            base.on_cc_visibility_change (visible);
        }
    }

    class SystemStatsFixture : Widgets.SystemStats {
        public uint visibility_calls = 0;

        public SystemStatsFixture (GpuFixture gpu) {
            base ("", true, true);
            replace_gpu_widget (gpu);
        }

        protected override async void update_sample (Cancellable cancellable) {
        }

        public void seed (SystemData.SystemSample sample) {
            apply_system_sample (sample);
        }

        public override void on_cc_visibility_change (bool visible) {
            visibility_calls++;
            base.on_cc_visibility_change (visible);
        }
    }

    class BatteryFixture : Widgets.Battery {
        public uint visibility_calls = 0;

        public BatteryFixture () {
            base ("", true, true);
        }

        protected override async void update_sample (Cancellable cancellable) {
        }

        public void seed (SystemData.BatterySample[] samples) {
            apply_batteries (samples);
        }

        public override void on_cc_visibility_change (bool visible) {
            visibility_calls++;
            base.on_cc_visibility_change (visible);
        }
    }

    Variant snapshot (string contents) {
        try {
            return Variant.parse (new VariantType ("a{oa{sa{sv}}}"), contents);
        } catch (VariantParseError e) {
            error ("Invalid widget fixture: %s", e.message);
        }
    }

    Variant bluetooth_snapshot () {
        return snapshot ("{" +
                         "'/adapter': {'org.bluez.Adapter1': {'Powered': <true>}}," +
                         "'/one': {'org.bluez.Device1': {'Connected': <true>, 'Alias': <'Keyboard'>}},"
                         +
                         "'/two': {'org.bluez.Device1': {'Connected': <true>, 'Alias': <'Mouse'>}},"
                         +
                         "'/three': {'org.bluez.Device1': {'Connected': <true>, 'Alias': <'Headphones'>}}}");
    }

    Variant ethernet_snapshot (string address, bool ipv6 = false) {
        string config_key = ipv6 ? "Ip6Config" : "Ip4Config";
        string iface = ipv6 ? "org.freedesktop.NetworkManager.IP6Config"
            : "org.freedesktop.NetworkManager.IP4Config";
        string path = ipv6 ? "/ip6" : "/ip4";
        return snapshot ("{" +
                         "'/org/freedesktop/NetworkManager': {'org.freedesktop.NetworkManager': {'PrimaryConnection': <objectpath '/ethernet_connection'>}},"
                         +
                         "'/ethernet_connection': {'org.freedesktop.NetworkManager.Connection.Active': {'Devices': <[objectpath '/ethernet_device']>, '"
                         +
                         config_key + "': <objectpath '" + path + "'>}}," +
                         "'/ethernet_device': {'org.freedesktop.NetworkManager.Device': {'State': <uint32 100>, 'DeviceType': <uint32 1>, 'Interface': <'enp1s0'>}},"
                         +
                         "'" + path + "': {'" + iface + "': {'AddressData': <[{'address': <'" +
                         address + "'>}]>}}}");
    }

    Variant wifi_unknown_strength_snapshot () {
        return snapshot ("{" +
                         "'/org/freedesktop/NetworkManager': {'org.freedesktop.NetworkManager': {'PrimaryConnection': <objectpath '/wifi_connection'>}},"
                         +
                         "'/wifi_connection': {'org.freedesktop.NetworkManager.Connection.Active': {'Devices': <[objectpath '/wifi_device']>}},"
                         +
                         "'/wifi_device': {'org.freedesktop.NetworkManager.Device': {'State': <uint32 100>, 'DeviceType': <uint32 2>, 'Interface': <'wlan0'>}, 'org.freedesktop.NetworkManager.Device.Wireless': {'ActiveAccessPoint': <objectpath '/ap'>}},"
                         +
                         "'/ap': {'org.freedesktop.NetworkManager.AccessPoint': {'Ssid': <[byte 0x53, byte 0x74, byte 0x75, byte 0x64, byte 0x69, byte 0x6f]>}}}");
    }

    Variant wifi_snapshot (uint strength) {
        return snapshot (("{" +
                          "'/org/freedesktop/NetworkManager': {'org.freedesktop.NetworkManager': {'PrimaryConnection': <objectpath '/wifi_connection'>}},"
                          +
                          "'/wifi_connection': {'org.freedesktop.NetworkManager.Connection.Active': {'Devices': <[objectpath '/wifi_device']>}},"
                          +
                          "'/wifi_device': {'org.freedesktop.NetworkManager.Device': {'State': <uint32 100>, 'DeviceType': <uint32 2>, 'Interface': <'wlan0'>}, 'org.freedesktop.NetworkManager.Device.Wireless': {'ActiveAccessPoint': <objectpath '/ap'>}},"
                          +
                          "'/ap': {'org.freedesktop.NetworkManager.AccessPoint': {'Ssid': <[byte 0x53, byte 0x74, byte 0x75, byte 0x64, byte 0x69, byte 0x6f]>, 'Strength': <byte %u>}}}")
                          .printf (strength));
    }

    Variant information_bluetooth_snapshot () {
        return snapshot ("{" +
                         "'/adapter': {'org.bluez.Adapter1': {'Powered': <true>}}," +
                         "'/one': {'org.bluez.Device1': {'Connected': <true>, 'Alias': <'Headphones'>, 'Icon': <'audio-headset'>}, 'org.bluez.Battery1': {'Percentage': <byte 0>}},"
                         +
                         "'/two': {'org.bluez.Device1': {'Connected': <true>, 'Alias': <'A very long keyboard name for layout testing'>, 'Icon': <'input-keyboard'>}},"
                         +
                         "'/three': {'org.bluez.Device1': {'Connected': <true>, 'Alias': <'Mouse'>, 'Icon': <'input-mouse'>}}}");
    }

    SystemData.SystemSample system_sample (uint64 total, uint64 idle,
                                           double memory_used = 8.2) {
        var sample = new SystemData.SystemSample ();
        var cpu = new SystemData.CpuTimes ();
        cpu.total = total;
        cpu.idle = idle;
        sample.cpu = cpu;
        sample.frequency_ghz = 3.4;
        sample.memory_used_gib = memory_used;
        sample.memory_total_gib = 32;
        return sample;
    }

    SystemData.BatterySample battery_sample (string name, string state, double percentage,
                                             double limit) {
        var sample = new SystemData.BatterySample ();
        sample.name = name;
        sample.state = state;
        sample.percentage = percentage;
        sample.limit = limit;
        sample.power = 12800000;
        sample.energy_now = 4800000;
        sample.energy_full = 80000000;
        sample.external_power = state == "Not charging";
        sample.start_threshold = 75;
        return sample;
    }

    Gtk.Widget ? find_widget (Gtk.Widget root, string css_class) {
        if (root.has_css_class (css_class)) {
            return root;
        }
        for (var child = root.get_first_child (); child != null;
             child = child.get_next_sibling ()) {
            var found = find_widget (child, css_class);
            if (found != null) {
                return found;
            }
        }
        return null;
    }

    Gtk.Widget ? find_meter (Gtk.Widget root, string name) {
        if (root.has_css_class ("information-meter") &&
            find_label_text (root, name) != null) {
            return root;
        }
        for (var child = root.get_first_child (); child != null;
             child = child.get_next_sibling ()) {
            var found = find_meter (child, name);
            if (found != null) {
                return found;
            }
        }
        return null;
    }

    Gtk.Label ? find_label_class (Gtk.Widget root, string css_class) {
        if (root is Gtk.Label && root.has_css_class (css_class)) {
            return (Gtk.Label) root;
        }
        for (var child = root.get_first_child (); child != null;
             child = child.get_next_sibling ()) {
            var found = find_label_class (child, css_class);
            if (found != null) {
                return found;
            }
        }
        return null;
    }

    Gtk.Label ? find_label_class_text (Gtk.Widget root, string css_class, string text) {
        if (root is Gtk.Label && root.has_css_class (css_class) &&
            ((Gtk.Label) root).label == text) {
            return (Gtk.Label) root;
        }
        for (var child = root.get_first_child (); child != null;
             child = child.get_next_sibling ()) {
            var found = find_label_class_text (child, css_class, text);
            if (found != null) {
                return found;
            }
        }
        return null;
    }

    uint css_count (Gtk.Widget root, string css_class) {
        uint count = root.has_css_class (css_class) ? 1 : 0;
        for (var child = root.get_first_child (); child != null;
             child = child.get_next_sibling ()) {
            count += css_count (child, css_class);
        }
        return count;
    }

    void drain () {
        while (MainContext.default ().pending ()) {
            MainContext.default ().iteration (false);
        }
    }

    void wait_for_timeout (uint milliseconds) {
        var loop = new MainLoop ();
        Timeout.add (milliseconds, () => {
            loop.quit ();
            return Source.REMOVE;
        });
        loop.run ();
        drain ();
    }

    Gtk.Label ? find_label_text (Gtk.Widget root, string text) {
        if (root is Gtk.Label && ((Gtk.Label) root).label == text) {
            return (Gtk.Label) root;
        }
        for (var child = root.get_first_child (); child != null;
             child = child.get_next_sibling ()) {
            var found = find_label_text (child, text);
            if (found != null) {
                return found;
            }
        }
        return null;
    }

    Gtk.LevelBar ? find_level_bar (Gtk.Widget root) {
        if (root is Gtk.LevelBar) {
            return (Gtk.LevelBar) root;
        }
        for (var child = root.get_first_child (); child != null;
             child = child.get_next_sibling ()) {
            var found = find_level_bar (child);
            if (found != null) {
                return found;
            }
        }
        return null;
    }

    uint visible_css_count (Gtk.Widget root, string css_class) {
        uint count = root.has_css_class (css_class) && root.visible ? 1 : 0;
        for (var child = root.get_first_child (); child != null;
             child = child.get_next_sibling ()) {
            count += visible_css_count (child, css_class);
        }
        return count;
    }

    void load_fixture_css () {
        string ?path = Environment.get_variable ("SWAYNC_PRIVATE_WIDGET_CSS");
        assert_nonnull (path);
        fixture_css_provider = new Gtk.CssProvider ();
        fixture_css_provider.parsing_error.connect ((section, error) => {
            fixture_css_errors++;
            warning ("Compiled fixture CSS: %s", error.message);
        });
        fixture_css_provider.load_from_path (path);
        Gtk.StyleContext.add_provider_for_display (Gdk.Display.get_default (),
                                                   fixture_css_provider,
                                                   Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
        assert (fixture_css_errors == 0);
    }

    void capture_widget (Gtk.Window window, Gtk.Widget widget, string path) {
        // Fixture updates invalidate the cached render node until the next frame.
        widget.queue_draw ();
        wait_for_timeout (80);
        int width = widget.get_width ();
        int height = widget.get_height ();
        assert (width > 0 && height > 0);
        var paintable = new Gtk.WidgetPaintable (widget);
        var snapshot = new Gtk.Snapshot ();
        paintable.snapshot (snapshot, width, height);
        Gsk.RenderNode ?node = snapshot.to_node ();
        assert_nonnull (node);
        Gdk.Surface ?surface = window.get_surface ();
        assert_nonnull (surface);
        Gsk.Renderer ?renderer = Gsk.Renderer.for_surface (surface);
        assert_nonnull (renderer);
        Gdk.Texture texture = renderer.render_texture (node, null);
        assert (texture.save_to_png (path));
        renderer.unrealize ();
    }

    void test_keyboard () {
        var bluetooth = new BluetoothFixture ();
        bluetooth.seed (bluetooth_snapshot ());
        var volume = new Widgets.Volume ("");
        volume.add_css_class ("test-volume");
        // The real panel's template owns this box. Add controls without starting
        // audio or hardware readers; this test exercises their native GTK input.
        var scrolled = (Gtk.ScrolledWindow) control_center.get_child ();
        var viewport = (Gtk.Viewport) scrolled.get_child ();
        var box = (Gtk.Box) viewport.get_child ();
        box.prepend (volume);
        box.prepend (bluetooth);
        control_center.set_visibility (true);
        drain ();

        Gtk.EventControllerKey ?keys = null;
        notifications_widget.set_focusable (true);
        assert (notifications_widget.grab_focus ());
        var controllers = control_center.observe_controllers ();
        for (uint i = 0; i < controllers.get_n_items (); i++) {
            var controller = controllers.get_item (i);
            if (controller is Gtk.EventControllerKey &&
                ((Gtk.EventController) controller).get_propagation_phase () ==
                Gtk.PropagationPhase.CAPTURE &&
                ((Gtk.EventControllerKey) controller).key_pressed (Gdk.Key.Home, 0, 0)) {
                // GTK also installs capture controllers. Select the panel's
                // notification shortcut handler by its real history behavior.
                assert_null (keys);
                keys = (Gtk.EventControllerKey) controller;
            }
        }
        assert_nonnull (keys);
        var more = (Gtk.Button) find_widget (bluetooth, "bluetooth-more");
        assert_nonnull (more);
        assert (more.grab_focus ());
        assert (!keys.key_pressed (Gdk.Key.Tab, 0, 0));
        assert (!keys.key_pressed (Gdk.Key.ISO_Left_Tab, 0, Gdk.ModifierType.SHIFT_MASK));
        assert (!keys.key_pressed (Gdk.Key.space, 0, 0));
        assert (!keys.key_pressed (Gdk.Key.Return, 0, 0));
        assert (control_center.child_focus (Gtk.DirectionType.TAB_FORWARD));
        assert (control_center.get_focus () != more);
        assert (control_center.child_focus (Gtk.DirectionType.TAB_BACKWARD));
        assert (control_center.get_focus () == more);
        more.clicked ();
        assert (more.label == "Show less");

        // Volume's first child is the row containing its label, scale and toggle.
        var row = volume.get_first_child ();
        var slider = (Gtk.Range) row.get_first_child ().get_next_sibling ();
        assert_nonnull (slider);
        assert (slider.grab_focus ());
        assert (!keys.key_pressed (Gdk.Key.Right, 0, 0));
        assert (!keys.key_pressed (Gdk.Key.Home, 0, 0));
        assert (!keys.key_pressed (Gdk.Key.Return, 0, 0));

        assert (notifications_widget.grab_focus ());
        assert (control_center.get_focus () == notifications_widget);
        assert (keys.key_pressed (Gdk.Key.Home, 0, 0));
        assert (!keys.key_pressed (Gdk.Key.z, 0, 0));
        assert (!keys.key_pressed (Gdk.Key.Tab, 0, 0));
        var history_child = notifications_widget.get_first_child ();
        history_child.set_focusable (true);
        assert (history_child.grab_focus ());
        assert (keys.key_pressed (Gdk.Key.Home, 0, 0));
        assert (!keys.key_pressed (Gdk.Key.Tab, 0, 0));
        control_center.set_visibility (false);
        box.remove (bluetooth);
        box.remove (volume);
    }

    void test_fresh_opening () {
        var network = new NetworkFixture ();
        network.seed (snapshot ("{'/org/freedesktop/NetworkManager': " +
                                "{'org.freedesktop.NetworkManager': {}}}"));
        assert (network.visible);
        network.on_cc_visibility_change (true);
        assert (!network.visible);
        network.on_cc_visibility_change (false);

        var bluetooth = new BluetoothFixture ();
        bluetooth.seed (bluetooth_snapshot ());
        assert (bluetooth.visible);
        bluetooth.on_cc_visibility_change (true);
        assert (!bluetooth.visible);
        bluetooth.on_cc_visibility_change (false);

        var battery = new Widgets.Battery ("");
        battery.visible = true;
        battery.on_cc_visibility_change (true);
        assert (!battery.visible);
        battery.on_cc_visibility_change (false);

        var system = new Widgets.SystemStats ("");
        var grid = (Gtk.Grid) system.get_first_child ();
        var cpu = (Gtk.Label) grid.get_child_at (1, 0);
        var ram = (Gtk.Label) grid.get_child_at (1, 1);
        cpu.label = ram.label = "Old reading";
        ram.tooltip_text = "Old total";
        system.on_cc_visibility_change (true);
        assert (cpu.label == "—" && ram.label == "—");
        assert (ram.tooltip_text == null);
        system.on_cc_visibility_change (false);
        drain ();
    }

    void test_title_inline_dnd_binding () {
        noti_daemon.dnd = false;

        var default_title = new Widgets.Title ("default");
        assert_null (find_widget (default_title, "title-inline-dnd"));

        var title = new Widgets.Title ("inline");
        var group = (Gtk.Box) find_widget (title, "title-inline-dnd");
        assert_nonnull (group);
        var dnd_label = (Gtk.Label) group.get_first_child ();
        assert (dnd_label.label == "DND");
        assert (dnd_label.tooltip_text == "Do Not Disturb");

        var dnd_switch = (Gtk.Switch) dnd_label.get_next_sibling ();
        assert (!dnd_switch.active);
        assert (dnd_switch.focusable);
        assert (dnd_switch.tooltip_text == "Do Not Disturb");
        assert_nonnull (find_widget (title, "control-center-clear-all"));

        dnd_switch.set_active (true);
        assert (noti_daemon.dnd);
        dnd_switch.set_active (false);
        assert (!noti_daemon.dnd);

        // External DND changes update the bound switch as well.
        noti_daemon.dnd = true;
        assert (dnd_switch.active);
        noti_daemon.dnd = false;
        assert (!dnd_switch.active);
    }

    void test_clock_lifecycle_and_formats () {
        var clock = new ClockFixture ();
        clock.value = new DateTime.utc (2026, 11, 1, 13, 4, 8.0);
        var time = (Gtk.Label) find_widget (clock, "clock-time");
        var date = (Gtk.Label) find_widget (clock, "clock-date");
        assert_nonnull (time);
        assert_nonnull (date);

        var scrolled = (Gtk.ScrolledWindow) control_center.get_child ();
        var viewport = (Gtk.Viewport) scrolled.get_child ();
        var box = (Gtk.Box) viewport.get_child ();
        box.append (clock);
        control_center.set_visibility (true);
        clock.on_cc_visibility_change (true);
        assert (time.label == "13:04");
        assert (date.label == clock.value.format ("%a, %b %-d"));
        assert (clock.reads == 1);

        clock.value = new DateTime.utc (2026, 11, 2, 23, 59, 9.0);
        wait_for_timeout (1200);
        assert (clock.reads >= 2);
        assert (time.label == "23:59");
        assert (date.label == clock.value.format ("%a, %b %-d"));

        clock.on_cc_visibility_change (false);
        uint reads_closed = clock.reads;
        clock.value = new DateTime.utc (2026, 11, 3, 8, 6, 5.0);
        wait_for_timeout (1200);
        assert (clock.reads == reads_closed);

        // Reopening samples immediately instead of reusing the prior display.
        clock.on_cc_visibility_change (true);
        assert (clock.reads == reads_closed + 1);
        assert (time.label == "08:06");
        assert (date.label == clock.value.format ("%a, %b %-d"));

        // Removing a rooted widget also retires its timer.
        uint reads_unrooted = clock.reads;
        box.remove (clock);
        wait_for_timeout (1200);
        assert (clock.reads == reads_unrooted);
        control_center.set_visibility (false);

        var formatted = new ClockFixture ("formatted");
        formatted.value = new DateTime.utc (2026, 11, 1, 13, 4, 8.0);
        var formatted_time = (Gtk.Label) find_widget (formatted, "clock-time");
        var formatted_date = (Gtk.Label) find_widget (formatted, "clock-date");
        assert_nonnull (formatted_time);
        assert_nonnull (formatted_date);
        formatted.on_cc_visibility_change (true);
        assert (formatted_time.label == formatted.value.format ("%I:%M:%S %p"));
        assert (formatted_time.label != formatted.value.format ("%H:%M:%S"));
        assert (formatted_date.label == "2026-11-01");

        formatted.value = new DateTime.utc (2026, 11, 2, 0, 5, 9.0);
        wait_for_timeout (1200);
        assert (formatted_time.label == formatted.value.format ("%I:%M:%S %p"));
        assert (formatted_date.label == "2026-11-02");
        formatted.on_cc_visibility_change (false);
    }

    void test_information_widget () {
        assert_nonnull (fixture_css_provider);
        assert (fixture_css_errors == 0);
        // A marker must not retain its owning meter through the draw callback.
        var release_host = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        Widgets.InformationMeter ?release_meter = new Widgets.InformationMeter ("Battery");
        var meter_reference = WeakRef (release_meter);
        release_host.append (release_meter);
        release_meter.set_reported_limit (80);
        release_host.remove (release_meter);
        release_meter = null;
        assert_null (meter_reference.get ());
        reload_test_config ("{\"layer-shell\": false, " +
                            "\"widgets\": [\"notifications\"], " +
                            "\"widget-config\": {\"notifications\": {}, " +
                            "\"clock\": {}, \"system-stats\": {\"interval\": 1}, " +
                            "\"gpu\": {\"interval\": 2}, " +
                            "\"battery\": {\"interval\": 5}}}");

        var clock = new ClockFixture ();
        clock.value = new DateTime.utc (2026, 11, 4, 14, 22, 0.0);
        var gpu = new GpuFixture ();
        var system = new SystemStatsFixture (gpu);
        var network = new NetworkFixture (true);
        var bluetooth = new BluetoothFixture (true);
        var battery = new BatteryFixture ();
        var information = new Widgets.Information.with_widgets (
            "", clock, system, network, bluetooth, battery);

        bool is_notifications;
        var factory_widget = Widgets.get_widget_from_key ("information", out is_notifications);
        assert (!is_notifications && factory_widget is Widgets.Information);

        var window = new Gtk.Window ();
        window.set_decorated (false);
        window.set_default_size (448, 420);
        window.set_child (information);
        app.add_window (window);
        window.present ();
        information.on_cc_visibility_change (true);
        wait_for_timeout (80);

        assert (information.has_css_class ("widget-information"));
        assert (visible_css_count (information, "information-divider") == 1);
        Gtk.Label ?clock_time = find_label_text (information, "14:22");
        Gtk.Label ?clock_date = find_label_text (information, "Wed, Nov 4");
        assert_nonnull (clock_time);
        assert_nonnull (clock_date);
        assert (clock_time.xalign == 0 && clock_date.xalign == 0);
        assert (clock_time.has_css_class ("clock-time") &&
                clock_date.has_css_class ("clock-date"));

        Gtk.Label ?connection_heading = find_label_text (information, "Connections");
        Gtk.Label ?battery_heading = find_label_text (information, "Battery");
        assert_nonnull (connection_heading);
        assert_nonnull (battery_heading);
        assert (!connection_heading.get_parent ().visible);
        assert (!battery_heading.get_parent ().visible);
        assert (clock.visibility_calls == 1 && system.visibility_calls == 1);
        assert (network.visibility_calls == 1 && bluetooth.visibility_calls == 1);
        assert (battery.visibility_calls == 1 && gpu.visibility_calls == 1);

        var cpu_meter = find_meter (system, "CPU");
        var ram_meter = find_meter (system, "RAM");
        assert_nonnull (cpu_meter);
        assert_nonnull (ram_meter);
        Gtk.LevelBar ?cpu_level = find_level_bar (cpu_meter);
        Gtk.LevelBar ?ram_level = find_level_bar (ram_meter);
        assert_nonnull (cpu_level);
        assert_nonnull (ram_level);
        assert (!cpu_level.visible);
        assert (find_widget (cpu_meter, "information-meter-unavailable").visible);

        // CPU needs two typed snapshots. A real zero is rendered as a real zero,
        // while the first unknown delta never exposes a zero-valued bar.
        system.seed (system_sample (100, 70));
        assert (!cpu_level.visible);
        system.seed (system_sample (200, 130));
        assert (cpu_level.visible && cpu_level.get_value () == 40);
        system.seed (system_sample (300, 230, 0));
        assert (cpu_level.visible && cpu_level.get_value () == 0);
        Gtk.Label ?zero_cpu = find_label_class (cpu_meter, "information-meter-value");
        assert_nonnull (zero_cpu);
        assert (zero_cpu.label == SystemData.percentage (0));
        assert (ram_level.visible && ram_level.get_value () == 0);
        system.seed (system_sample (400, 287, 8.2));
        assert (cpu_level.visible && cpu_level.get_value () == 43);
        assert (ram_level.visible && ram_level.get_value () == 26);
        assert (find_label_text (ram_meter, "8.2 / 32 GiB") != null);

        var asleep = new GpuData.Sample ("0000:01:00.0");
        asleep.state = "Asleep";
        gpu.seed ({ asleep });
        assert (!gpu.visible);
        var missing_reading = new GpuData.Sample ("0000:01:00.0");
        missing_reading.runtime_active = true;
        gpu.seed ({ missing_reading });
        assert (gpu.visible);
        var gpu_meter = find_meter (gpu, "GPU");
        assert_nonnull (gpu_meter);
        Gtk.LevelBar ?gpu_level = find_level_bar (gpu_meter);
        assert_nonnull (gpu_level);
        assert (!gpu_level.visible);
        var active = new GpuData.Sample ("0000:01:00.0");
        active.runtime_active = true;
        assert (active.parse ("1200, 18, 1638, 8192"));
        gpu.seed ({ active });
        assert (gpu.visible && gpu_level.visible && gpu_level.get_value () == 18);
        var vram_meter = find_meter (gpu, "VRAM");
        assert_nonnull (vram_meter);
        Gtk.LevelBar ?vram_level = find_level_bar (vram_meter);
        assert_nonnull (vram_level);
        assert (vram_level.visible && vram_level.get_value () == 20);
        drain ();
        wait_for_timeout (40);
        Graphene.Rect cpu_bounds;
        Graphene.Rect ram_bounds;
        Graphene.Rect gpu_bounds;
        Graphene.Rect vram_bounds;
        assert (cpu_meter.compute_bounds (system, out cpu_bounds));
        assert (ram_meter.compute_bounds (system, out ram_bounds));
        assert (gpu_meter.compute_bounds (system, out gpu_bounds));
        assert (vram_meter.compute_bounds (system, out vram_bounds));
        assert (Math.fabs (cpu_bounds.origin.y - ram_bounds.origin.y) < 1);
        assert (Math.fabs (gpu_bounds.origin.y - vram_bounds.origin.y) < 1);
        assert (gpu_bounds.origin.y > cpu_bounds.origin.y + 1);

        SystemData.BatterySample[] no_batteries = {};
        battery.seed (no_batteries);
        network.seed (snapshot ("{}"));
        bluetooth.seed (snapshot ("{}"));
        assert (!connection_heading.get_parent ().visible);
        assert (!battery_heading.get_parent ().visible);
        assert (visible_css_count (information, "information-divider") == 1);

        // Ethernet uses a labelled icon cell and a right-aligned IP value.
        network.seed (ethernet_snapshot ("192.0.2.10"));
        assert (connection_heading.get_parent ().visible);
        assert (visible_css_count (information, "information-divider") == 2);
        assert (find_label_text (network, "Ethernet") != null);
        Gtk.Label ?ip = find_label_text (network, "192.0.2.10");
        assert_nonnull (ip);
        assert (ip.xalign == 1 && ip.single_line_mode);
        assert (ip.ellipsize == Pango.EllipsizeMode.END);
        assert (ip.tooltip_text == "192.0.2.10");
        wait_for_timeout (80);
        assert (ip.get_width () > 80 && !ip.get_layout ().is_ellipsized ());
        string ?ethernet_capture = Environment.get_variable ("SWAYNC_PRIVATE_WIDGET_SCREENSHOT");
        if (ethernet_capture != null) {
            capture_widget (window, information, ethernet_capture + "-ethernet.png");
        }

        // IPv6 fallback stays constrained to the right cell at the configured width.
        string long_ipv6 = "2001:db8:abcd:1234:5678:90ab:cdef:1234";
        network.seed (ethernet_snapshot (long_ipv6, true));
        drain ();
        assert (find_label_text (network, long_ipv6) != null);
        ip = find_label_text (network, long_ipv6);
        assert_nonnull (ip);
        assert (ip.tooltip_text == long_ipv6 && ip.get_width () < 300);
        assert (information.get_width () <= 448 && network.get_width () <= 448);

        // Unknown Wi-Fi strength uses the generic wireless glyph and an unknown
        // percentage instead of the full-strength icon.
        network.seed (wifi_unknown_strength_snapshot ());
        Gtk.Label ?unknown_strength = find_label_text (network, "—");
        assert_nonnull (unknown_strength);
        assert (unknown_strength.tooltip_text == "Wi-Fi signal unavailable");
        assert_nonnull (find_widget (network, "information-wifi-signal-unknown"));

        bluetooth.seed (information_bluetooth_snapshot ());
        assert (connection_heading.get_parent ().visible);
        Gtk.Label ?long_device = find_label_text (
            bluetooth, "A very long keyboard name for layout testing");
        assert_nonnull (long_device);
        assert (long_device.single_line_mode &&
                long_device.ellipsize == Pango.EllipsizeMode.END);
        assert (long_device.tooltip_text == "A very long keyboard name for layout testing");
        Gtk.Label ?device_zero = find_label_class_text (
            bluetooth, "information-device-value", SystemData.percentage (0));
        Gtk.Label ?device_unknown = find_label_class_text (
            bluetooth, "information-device-value", "—");
        assert_nonnull (device_zero);
        assert_nonnull (device_unknown);
        assert (device_zero.tooltip_text == "Battery");
        assert (device_unknown.tooltip_text == "Battery not reported");
        var more = (Gtk.Button) find_widget (bluetooth, "bluetooth-more");
        assert_nonnull (more);
        assert (more.visible && more.label == "+1 more");
        more.clicked ();
        assert (more.label == "Show less");
        wait_for_timeout (20);
        Graphene.Rect device_grid_bounds;
        Graphene.Rect more_bounds;
        Gtk.Widget ?device_grid = find_widget (bluetooth, "information-device-grid");
        assert_nonnull (device_grid);
        assert (device_grid.compute_bounds (bluetooth, out device_grid_bounds));
        assert (more.compute_bounds (bluetooth, out more_bounds));
        assert (more_bounds.origin.y > device_grid_bounds.origin.y);

        var low = battery_sample ("BAT0", "Discharging", 9, -1);
        battery.seed ({ low });
        assert (battery_heading.get_parent ().visible);
        assert (visible_css_count (information, "information-divider") == 3);
        var battery_meter = find_widget (battery, "information-battery-meter");
        assert_nonnull (battery_meter);
        Gtk.LevelBar ?battery_level = find_level_bar (battery_meter);
        assert_nonnull (battery_level);
        assert (battery_level.visible && battery_level.get_value () == 9);
        assert (css_count (battery_meter, "information-limit-marker") == 0);
        Gtk.Label ?battery_state = find_label_class (
            battery_meter, "information-battery-state");
        assert_nonnull (battery_state);
        assert (battery_state.label == "Low · Discharging");
        assert (battery_state.xalign == 1 && css_count (battery_meter,
                                                        "information-battery-state") == 1);
        assert (battery_meter.has_css_class ("information-meter-critical"));
        assert_null (gtk_test_accessible_check_property (
                         battery_level, Gtk.AccessibleProperty.DESCRIPTION,
                         "Low battery. Discharging."));
        assert (find_label_text (battery_meter, "BAT0") == null);

        var unknown_battery = battery_sample ("BAT0", "Unknown", -1, -1);
        battery.seed ({ unknown_battery });
        assert (!battery_level.visible);
        assert (find_widget (battery_meter, "information-meter-unavailable").visible);
        var charging = battery_sample ("BAT0", "Charging", 64, 80);
        battery.seed ({ charging });
        assert (battery_level.visible && battery_level.get_value () == 64);
        assert (battery_meter.has_css_class ("information-meter-charging"));
        assert (css_count (battery_meter, "information-limit-marker") == 1);

        var resting = battery_sample ("BAT0", "Not charging", 80, 80);
        battery.seed ({ resting });
        assert (battery_state.label == "Idle at 80%");
        wait_for_timeout (40);
        assert (!battery_state.get_layout ().is_ellipsized ());
        assert (css_count (battery_meter, "information-limit-marker") == 1);
        Gtk.Widget ?rates = find_widget (battery, "information-battery-rates");
        assert_nonnull (rates);
        assert (!rates.visible);

        var second_battery = battery_sample ("BAT1", "Discharging", 51, -1);
        battery.seed ({ resting, second_battery });
        assert (css_count (battery, "information-battery-meter") == 2);
        assert (find_label_text (battery, "BAT0 ·") != null);
        assert (find_label_text (battery, "BAT1 ·") != null);
        battery.seed ({ resting });
        network.seed (wifi_snapshot (72));

        string ?screenshot = Environment.get_variable ("SWAYNC_PRIVATE_WIDGET_SCREENSHOT");
        if (screenshot != null) {
            drain ();
            capture_widget (window, information, screenshot);
        }

        uint clock_reads = clock.reads;
        information.on_cc_visibility_change (false);
        assert (clock.visibility_calls == 2 && system.visibility_calls == 2);
        assert (network.visibility_calls == 2 && bluetooth.visibility_calls == 2);
        assert (battery.visibility_calls == 2 && gpu.visibility_calls == 2);
        assert (more.label == "+1 more");
        wait_for_timeout (1100);
        assert (clock.reads == clock_reads);

        // Reopening clears the old CPU/GPU/battery values before fresh fixtures
        // arrive, and the optional sections can reappear from new snapshots.
        information.on_cc_visibility_change (true);
        assert (clock.visibility_calls == 3 && system.visibility_calls == 3);
        assert (network.visibility_calls == 3 && bluetooth.visibility_calls == 3);
        assert (battery.visibility_calls == 3 && gpu.visibility_calls == 3);
        assert (!cpu_level.visible && !gpu.visible && !battery.visible);
        assert (!connection_heading.get_parent ().visible &&
                !battery_heading.get_parent ().visible);
        assert (visible_css_count (information, "information-divider") == 1);
        network.seed (ethernet_snapshot ("192.0.2.10"));
        battery.seed ({ resting });
        assert (connection_heading.get_parent ().visible &&
                battery_heading.get_parent ().visible);

        // Replacing the rooted composite follows the same child unroot cleanup
        // used when a real widget reload swaps the control-center tree.
        clock_reads = clock.reads;
        information.on_cc_visibility_change (false);
        var replacement_clock = new ClockFixture ();
        replacement_clock.value = new DateTime.utc (2026, 11, 4, 14, 23, 0.0);
        var replacement_gpu = new GpuFixture ();
        var replacement_system = new SystemStatsFixture (replacement_gpu);
        var replacement_network = new NetworkFixture (true);
        var replacement_bluetooth = new BluetoothFixture (true);
        var replacement_battery = new BatteryFixture ();
        var replacement = new Widgets.Information.with_widgets (
            "", replacement_clock, replacement_system, replacement_network,
            replacement_bluetooth, replacement_battery);
        window.set_child (replacement);
        replacement.on_cc_visibility_change (true);
        wait_for_timeout (40);
        assert (replacement_clock.visibility_calls == 1);
        assert (visible_css_count (replacement, "information-divider") == 1);
        uint replacement_reads = replacement_clock.reads;
        assert (replacement_reads == 1);
        window.set_child (null);
        window.destroy ();
        wait_for_timeout (1100);
        assert (clock.reads == clock_reads);
        assert (replacement_clock.reads == replacement_reads);
    }

    void reload_test_config (string contents) {
        try {
            FileUtils.set_contents (test_config_path, contents);
            swaync_daemon.reload_config ();
        } catch (Error e) {
            error ("Clock reload fixture failed: %s", e.message);
        }
    }

    void test_clock_reload_removal () {
        reload_test_config ("{\"layer-shell\": false, " +
                            "\"widgets\": [\"clock\", \"title\", \"notifications\"], " +
                            "\"widget-config\": {\"clock\": {\"time-format\": \"%H:%M:%S\"}, " +
                            "\"title\": {\"show-dnd\": true}, " +
                            "\"notifications\": {}}}");
        control_center.set_visibility (true);
        drain ();

        Gtk.Widget ?old_clock_widget = find_widget (control_center, "widget-clock");
        assert_nonnull (old_clock_widget);
        var old_clock = (Widgets.Clock) old_clock_widget;
        var old_time = (Gtk.Label) find_widget (old_clock, "clock-time");
        assert_nonnull (old_time);
        string last_time = old_time.label;
        assert (last_time.length > 0);
        assert_nonnull (find_widget (control_center, "title-inline-dnd"));

        // Use the application's real config reload path to replace both widgets.
        reload_test_config ("{\"layer-shell\": false, " +
                            "\"widgets\": [\"title\", \"notifications\"], " +
                            "\"widget-config\": {\"title\": {}, " +
                            "\"notifications\": {}}}");
        assert_null (find_widget (control_center, "widget-clock"));
        assert_null (find_widget (control_center, "title-inline-dnd"));
        wait_for_timeout (1300);
        assert (old_time.label == last_time);
        control_center.set_visibility (false);
    }

    public int main (string[] args) {
        assert (Environment.get_variable ("SWAYNC_PRIVATE_WIDGET_TEST") == "1");
        Test.init (ref args);
        Gtk.init ();
        Adw.init ();
        Functions.init ();
        load_fixture_css ();
        try {
            string directory = DirUtils.make_tmp ("swaync-widget-test-XXXXXX");
            string config = Path.build_filename (directory, "config.json");
            test_config_path = config;
            FileUtils.set_contents (config,
                                    "{\"layer-shell\": false, \"widgets\": [\"notifications\"]," +
                                    "\"widget-config\": {\"system-stats\": {\"interval\": 1}," +
                                    "\"battery\": {\"interval\": 5}, \"notifications\": {}," +
                                    "\"clock\": {}, " +
                                    "\"clock#formatted\": {\"time-format\": \"%I:%M:%S %p\", " +
                                    "\"date-format\": \"%Y-%m-%d\"}," +
                                    "\"title#default\": {}, " +
                                    "\"title#inline\": {\"show-dnd\": true}, " +
                                    "\"volume\": {\"show-per-app\": true}}}");
            ConfigModel.init (config);
            self_settings = new Settings ("org.erikreider.swaync");
            app = new Swaync (false);
            app.use_layer_shell = false;
            monitors = Gdk.Display.get_default ().get_monitors ();
            noti_daemon = new NotiDaemon (Bus.get_sync (BusType.SESSION));
            swaync_daemon = new SwayncDaemon ();
            notifications_widget = new Widgets.Notifications ();
            control_center = new ControlCenter ();
            app.add_window (control_center);
            Test.add_func ("/widgets/keyboard-routing", test_keyboard);
            Test.add_func ("/widgets/fresh-opening", test_fresh_opening);
            Test.add_func ("/widgets/title-inline-dnd-binding",
                           test_title_inline_dnd_binding);
            Test.add_func ("/widgets/clock-lifecycle-and-formats",
                           test_clock_lifecycle_and_formats);
            Test.add_func ("/widgets/clock-reload-removal", test_clock_reload_removal);
            Test.add_func ("/widgets/information-composite", test_information_widget);
            int result = Test.run ();
            control_center.destroy ();
            FileUtils.remove (config);
            DirUtils.remove (directory);
            return result;
        } catch (Error e) {
            error ("Widget test setup failed: %s", e.message);
        }
    }
}

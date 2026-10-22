namespace SwayNotificationCenter.WidgetTests {
    class NetworkFixture : Widgets.Network {
        public NetworkFixture () {
            base ("");
        }

        public void seed (Variant snapshot) {
            apply_snapshot (snapshot);
        }
    }

    class BluetoothFixture : Widgets.Bluetooth {
        public BluetoothFixture () {
            base ("");
        }

        public void seed (Variant snapshot) {
            apply_snapshot (snapshot);
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

    void drain () {
        while (MainContext.default ().pending ()) {
            MainContext.default ().iteration (false);
        }
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

    public int main (string[] args) {
        assert (Environment.get_variable ("SWAYNC_PRIVATE_WIDGET_TEST") == "1");
        Test.init (ref args);
        Gtk.init ();
        Adw.init ();
        Functions.init ();
        try {
            string directory = DirUtils.make_tmp ("swaync-widget-test-XXXXXX");
            string config = Path.build_filename (directory, "config.json");
            FileUtils.set_contents (config,
                                    "{\"layer-shell\": false, \"widgets\": [\"notifications\"]," +
                                    "\"widget-config\": {\"system-stats\": {\"interval\": 1}," +
                                    "\"battery\": {\"interval\": 5}, \"notifications\": {}," +
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

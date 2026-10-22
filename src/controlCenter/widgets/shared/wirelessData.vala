namespace SwayNotificationCenter.Widgets.WirelessData {
    public Variant ?properties (Variant ?objects, string path, string iface) {
        if (objects == null || !objects.is_of_type (new VariantType ("a{oa{sa{sv}}}"))) {
            return null;
        }
        Variant ? interfaces = objects.lookup_value (path, null);
        return interfaces != null ?interfaces.lookup_value (iface, null) : null;
    }

    public string text (Variant ?props, string key, string fallback = "") {
        Variant ? value = props != null ?props.lookup_value (key, null) : null;

        return value != null &&
               (value.is_of_type (VariantType.STRING) || value.is_of_type (VariantType.OBJECT_PATH))
            ? value.get_string () : fallback;
    }

    public bool flag (Variant ?props, string key) {
        Variant ? value = props != null ?props.lookup_value (key, VariantType.BOOLEAN) : null;

        return value != null && value.get_boolean ();
    }

    public int number (Variant ?props, string key) {
        Variant ? value = props != null ?props.lookup_value (key, null) : null;

        if (value == null) {
            return -1;
        }
        if (value.is_of_type (VariantType.BYTE)) {
            return value.get_byte ();
        }
        if (value.is_of_type (VariantType.UINT32)) {
            uint n = value.get_uint32 ();
            return n <= int.MAX ? (int) n : -1;
        }
        return -1;
    }

    public class WifiSample : Object {
        public bool present = false;
        public string state = "Unavailable";
        public string ssid = "";
        public int strength = -1;

        public static WifiSample parse (Variant ?objects) {
            var sample = new WifiSample ();
            if (objects == null || !objects.is_of_type (new VariantType ("a{oa{sa{sv}}}"))) {
                return sample;
            }
            Variant ?manager = properties (objects, "/org/freedesktop/NetworkManager",
                                           "org.freedesktop.NetworkManager");
            var iterator = objects.iterator ();
            string path;
            Variant interfaces;
            while (iterator.next ("{o@a{sa{sv}}}", out path, out interfaces)) {
                Variant ?wifi =
                    interfaces.lookup_value ("org.freedesktop.NetworkManager.Device.Wireless",
                                             null);
                if (wifi == null) {
                    continue;
                }
                sample.present = true;
                sample.state = flag (manager, "WirelessEnabled") ? "Disconnected" : "Off";
                Variant ?device = interfaces.lookup_value ("org.freedesktop.NetworkManager.Device",
                                                           null);
                if (number (device, "State") != 100) {
                    continue;
                }
                Variant ?ap = properties (objects, text (wifi, "ActiveAccessPoint"),
                                          "org.freedesktop.NetworkManager.AccessPoint");
                if (ap == null) {
                    continue;
                }
                Variant ?ssid = ap.lookup_value ("Ssid", new VariantType ("ay"));
                if (ssid != null) {
                    var bytes = new StringBuilder ();
                    for (size_t i = 0; i < ssid.n_children (); i++) {
                        uint8 b = ssid.get_child_value (i).get_byte ();
                        if (b == 0 || b < 32 || b == 127) {
                            bytes.append_c (' ');
                        } else {
                            bytes.append_c ((char) b);
                        }
                    }
                    sample.ssid = bytes.str.make_valid ().strip ();
                }
                if (sample.ssid == "") {
                    sample.ssid = "Hidden network";
                }
                sample.state = "Connected";
                int strength = number (ap, "Strength");
                sample.strength = strength >= 0 && strength <= 100 ? strength : -1;
                break;
            }
            return sample;
        }
    }

    public class BluetoothDevice : Object {
        public string path;
        public string name;
        public int battery = -1;
    }

    public class BluetoothSample : Object {
        public bool present = false;
        public bool powered = false;
        public GenericArray<BluetoothDevice> devices = new GenericArray<BluetoothDevice> ();

        public static BluetoothSample parse (Variant ?objects) {
            var sample = new BluetoothSample ();
            if (objects == null || !objects.is_of_type (new VariantType ("a{oa{sa{sv}}}"))) {
                return sample;
            }
            var iterator = objects.iterator ();
            string path;
            Variant interfaces;
            while (iterator.next ("{o@a{sa{sv}}}", out path, out interfaces)) {
                Variant ?adapter = interfaces.lookup_value ("org.bluez.Adapter1", null);
                if (adapter != null) {
                    sample.present = true;
                    sample.powered = sample.powered || flag (adapter, "Powered");
                }
                Variant ?device = interfaces.lookup_value ("org.bluez.Device1", null);
                if (device == null || !flag (device, "Connected")) {
                    continue;
                }
                var entry = new BluetoothDevice ();
                entry.path = path;
                entry.name = text (device, "Alias",
                                   text (device, "Name", "Bluetooth device")).make_valid ();
                if (entry.name.strip () == "") {
                    entry.name = "Bluetooth device";
                }
                int percentage = number (interfaces.lookup_value ("org.bluez.Battery1", null),
                                         "Percentage");
                entry.battery = percentage >= 0 && percentage <= 100 ? percentage : -1;
                sample.devices.add (entry);
            }
            sample.devices.sort ((a, b) => {
                int order = a.name.collate (b.name);
                return order != 0 ? order : strcmp (a.path, b.path);
            });
            return sample;
        }
    }
}

namespace SwayNotificationCenter.Widgets {
    /** A coalesced ObjectManager reader with subscriptions owned by panel visibility. */
    public abstract class BusWidget : BaseWidget {
        string service;
        string path;
        Cancellable ?lifetime;
        DBusConnection ?connection;
        uint[] subscriptions = {};
        uint queued = 0;
        bool refreshing = false;
        bool dirty = false;

        protected BusWidget (string suffix, string service, string path) {
            base (suffix);
            this.service = service;
            this.path = path;
            visible = false;
        }

        protected abstract bool watches_interface (string iface);
        protected abstract void apply_snapshot (Variant ?objects);

        bool current (Cancellable token) {
            return lifetime == token && !token.is_cancelled ();
        }

        void queue_refresh (Cancellable token) {
            if (!current (token)) {
                return;
            }
            dirty = true;
            if (refreshing || queued != 0) {
                return;
            }
            queued = Timeout.add (150, () => {
                queued = 0;
                refresh.begin (token);
                return Source.REMOVE;
            });
        }

        async void refresh (Cancellable token) {
            if (!current (token) || connection == null || refreshing) {
                return;
            }
            refreshing = true;
            dirty = false;
            Variant ?objects = null;
            try {
                Variant reply = yield connection.call (service, path,
                                                       "org.freedesktop.DBus.ObjectManager",
                                                       "GetManagedObjects", null,
                                                       new VariantType ("(a{oa{sa{sv}}})"),
                                                       DBusCallFlags.NO_AUTO_START, 1500, token);

                objects = reply.get_child_value (0);
            } catch (Error e) {
                // A missing/restarting service does not retain stale device data.
            }
            if (!current (token)) {
                return;
            }
            apply_snapshot (objects);
            debug ("%s snapshot: %s", widget_name, objects != null ? "ready" : "unavailable");
            refreshing = false;
            if (dirty) {
                queue_refresh (token);
            }
        }

        async void start (Cancellable token) {
            try {
                var bus = yield Bus.get (BusType.SYSTEM, token);

                if (!current (token)) {
                    return;
                }
                connection = bus;
                subscriptions += bus.signal_subscribe (service, "org.freedesktop.DBus.Properties",
                                                       "PropertiesChanged", null, null,
                                                       DBusSignalFlags.NONE,
                                                       (c, sender, object_path, iface, member,
                                                        parameters) => {
                    if (watches_interface (parameters.get_child_value (0).get_string ())) {
                        queue_refresh (token);
                    }
                });
                subscriptions += bus.signal_subscribe (service,
                                                       "org.freedesktop.DBus.ObjectManager",
                                                       null, path, null, DBusSignalFlags.NONE,
                                                       (c, sender, object_path, iface, member,
                                                        parameters) => queue_refresh (token));
                subscriptions += bus.signal_subscribe ("org.freedesktop.DBus",
                                                       "org.freedesktop.DBus",
                                                       "NameOwnerChanged", "/org/freedesktop/DBus",
                                                       service, DBusSignalFlags.NONE,
                                                       (c, sender, object_path, iface, member,
                                                        parameters) => queue_refresh (token));
                debug ("%s subscription: started", widget_name);
                refresh.begin (token);
            } catch (Error e) {
                if (current (token)) {
                    apply_snapshot (null);
                }
            }
        }

        void stop () {
            if (queued != 0) {
                Source.remove (queued);
                queued = 0;
            }
            if (lifetime != null) {
                lifetime.cancel ();
                lifetime = null;
                debug ("%s subscription: stopped", widget_name);
            }
            if (connection != null) {
                foreach (uint id in subscriptions) {
                    connection.signal_unsubscribe (id);
                }
            }
            subscriptions = {};
            connection = null;
            refreshing = false;
            dirty = false;
        }

        public override void on_cc_visibility_change (bool visible) {
            stop ();
            if (visible) {
                // A previous connection/device list is not a fresh opening sample.
                apply_snapshot (null);
                var token = new Cancellable ();
                lifetime = token;
                start.begin (token);
            }
        }

        public override void unroot () {
            stop ();
            base.unroot ();
        }
    }
}

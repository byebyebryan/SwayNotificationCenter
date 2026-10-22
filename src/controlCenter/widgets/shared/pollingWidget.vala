namespace SwayNotificationCenter.Widgets {
    /** A visible-panel sampler; cancellation also retires in-flight reads on reload. */
    public abstract class PollingWidget : BaseWidget {
        uint timer_id = 0;
        Cancellable ?lifetime = null;
        bool refreshing = false;
        protected uint interval = 1;

        protected PollingWidget (string suffix) {
            base (suffix);
        }

        protected virtual void reset_sample () {
        }

        protected abstract async void update_sample (Cancellable cancellable);

        protected void configure_interval (uint default_interval) {
            interval = default_interval;
            Json.Object ?config = get_config (this);
            if (config != null) {
                bool found;
                int ?configured = get_prop<int> (config, "interval", out found);
                if (found && configured >= 1 && configured <= 3600) {
                    interval = (uint) configured;
                }
            }
        }

        protected static Gtk.Label add_metric (Gtk.Grid grid, int row, string title) {
            var label = new Gtk.Label (title);
            label.xalign = 0;
            label.add_css_class ("metric-label");
            var value = new Gtk.Label ("—");
            value.xalign = 1;
            value.hexpand = true;
            value.ellipsize = Pango.EllipsizeMode.END;
            value.max_width_chars = 1;
            value.add_css_class ("metric-value");
            grid.attach (label, 0, row);
            grid.attach (value, 1, row);
            return value;
        }

        async void refresh (Cancellable cancellable) {
            if (refreshing || lifetime != cancellable || cancellable.is_cancelled ()) {
                return;
            }
            refreshing = true;
            yield update_sample (cancellable);

            if (lifetime == cancellable) {
                refreshing = false;
            }
        }

        void stop () {
            if (timer_id != 0) {
                Source.remove (timer_id);
                timer_id = 0;
            }
            if (lifetime != null) {
                lifetime.cancel ();
                lifetime = null;
            }
            refreshing = false;
        }

        public override void on_cc_visibility_change (bool visible) {
            stop ();
            if (!visible) {
                return;
            }
            reset_sample ();
            var cancellable = new Cancellable ();
            lifetime = cancellable;
            refresh.begin (cancellable);
            // Millisecond timers give CPU usage its first full one-second sample promptly.
            timer_id = Timeout.add (interval * 1000, () => {
                refresh.begin (cancellable);
                return Source.CONTINUE;
            });
        }

        public override void unroot () {
            stop ();
            base.unroot ();
        }
    }
}

namespace SwayNotificationCenter {
    /** Bridges fork-owned age policy to the daemon's two notification views. */
    internal class NotificationHistory : Object {
        private unowned NotiDaemon daemon;
        private HistoryRetention retention = new HistoryRetention ();
        private Gee.HashMap<uint32, string> pending_closures =
            new Gee.HashMap<uint32, string> ();
        private uint cleanup_id = 0;
        private ulong config_handler = 0;

        public NotificationHistory (NotiDaemon daemon) {
            this.daemon = daemon;
            retention.expired.connect (expire);
            configure (ConfigModel.instance);
            config_handler = app.config_reload.connect ((old, config) => configure (config));
        }

        private void configure (ConfigModel config) {
            retention.configure (config.history_retention, config.history_retention_critical);
        }

        public void track (NotifyParams param) {
            retention.track (param.applied_id, param.action_revision, param.urgency.to_byte (),
                             param.resident);
            Notification ?history = notifications_widget.find_notification (param.applied_id);
            if (history != null) {
                set_reply_active (param, history.history_reply_active);
            }
        }

        public void set_reply_active (NotifyParams param, bool active) {
            retention.set_deferred (param.applied_id, param.action_revision, active);
        }

        public void forget (uint32 id) {
            retention.forget (id);
            pending_closures.unset (id);
        }

        public void clear () {
            retention.clear ();
            pending_closures.clear ();
        }

        public void shutdown () {
            retention.shutdown ();
            if (cleanup_id != 0) {
                Source.remove (cleanup_id);
                cleanup_id = 0;
            }
            if (config_handler != 0) {
                app.disconnect (config_handler);
                config_handler = 0;
            }
            pending_closures.clear ();
        }

        private void expire (uint32 id, string revision) {
            Notification ?notification = notifications_widget.find_notification (id);
            if (notification == null || daemon.find_action_notification (id) != notification
                || notification.param.action_revision != revision) {
                return;
            }

            pending_closures.set (id, revision);
            notifications_widget.remove_notification (id);
            finish_closure (id, revision);
            swaync_daemon.emit_subscribe ();
        }

        // History pruning must not shorten the current popup's lifetime.
        private void finish_closure (uint32 id, string revision) {
            if (pending_closures.get (id) != revision) {
                return;
            }
            Notification ?history = notifications_widget.find_notification (id);
            Notification ?popup = floating_notifications != null
                ? floating_notifications.find_notification (id) : null;

            if (history != null || (popup != null && popup.param.action_revision != revision)) {
                pending_closures.unset (id);
                return;
            }
            if (popup != null) {
                return;
            }
            pending_closures.unset (id);
            daemon.retire_notification_id (id, ClosedReasons.EXPIRED);
        }

        public void popup_removed (NotifyParams param) {
            if (pending_closures.get (param.applied_id) != param.action_revision ||
                cleanup_id != 0) {
                return;
            }
            // Replacements detach old widgets before admitting the new revision.
            // Reconcile once that transaction has finished, not in its middle.
            cleanup_id = Idle.add (() => {
                cleanup_id = 0;
                var ids = pending_closures.keys.to_array ();
                foreach (uint32 id in ids) {
                    string ?revision = pending_closures.get (id);
                    if (revision != null) {
                        finish_closure (id, revision);
                    }
                }
                return Source.REMOVE;
            });
        }
    }
}

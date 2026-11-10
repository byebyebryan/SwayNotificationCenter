using Gee;

namespace SwayNotificationCenter {
    [CCode (cname = "g_strerror", cheader_filename = "glib.h")]
    private extern unowned string retention_strerror (int error_number);

    [CCode (cname = "swaync_history_retention_boottime_now",
            cheader_filename = "historyRetentionTimer.h")]
    private extern bool retention_boottime_now (out int64 now_usec,
                                                out int error_number);

    [CCode (cname = "swaync_history_retention_timer_new",
            cheader_filename = "historyRetentionTimer.h")]
    private extern int retention_timer_new (out int error_number);

    [CCode (cname = "swaync_history_retention_timer_arm",
            cheader_filename = "historyRetentionTimer.h")]
    private extern bool retention_timer_arm (int fd,
                                             int64 deadline_usec,
                                             out int error_number);

    [CCode (cname = "swaync_history_retention_timer_disarm",
            cheader_filename = "historyRetentionTimer.h")]
    private extern bool retention_timer_disarm (int fd, out int error_number);

    [CCode (cname = "swaync_history_retention_timer_read",
            cheader_filename = "historyRetentionTimer.h")]
    private extern bool retention_timer_read (int fd,
                                              out bool consumed,
                                              out int error_number);

    [CCode (cname = "swaync_history_retention_timer_close",
            cheader_filename = "historyRetentionTimer.h")]
    private extern void retention_timer_close (int fd);

    internal interface HistoryRetentionClock : Object {
        public abstract bool read (out int64 now_usec, out string ?error_message);
    }

    internal interface HistoryRetentionScheduler : Object {
        public abstract bool arm (int64 deadline_usec, out string ?error_message);
        public abstract bool disarm (out string ?error_message);
        public abstract void shutdown ();

        public signal void fired ();
    }

    private class BoottimeRetentionClock : Object, HistoryRetentionClock {
        public bool read (out int64 now_usec, out string ?error_message) {
            int error_number;
            bool success = retention_boottime_now (out now_usec, out error_number);

            error_message = success ? null : format_errno (error_number);
            return success;
        }
    }

    private class TimerfdRetentionScheduler : Object, HistoryRetentionScheduler {
        private int _fd = -1;
        private uint _watch_id = 0;
        private IOChannel ?_channel;
        private string ?_creation_error;
        private bool _shutdown = false;

        public TimerfdRetentionScheduler () {
            int error_number;
            _fd = retention_timer_new (out error_number);
            if (_fd < 0) {
                _creation_error = format_errno (error_number);
                return;
            }

            IOChannel channel = new IOChannel.unix_new (_fd);
            channel.set_close_on_unref (false);
            _channel = channel;
            _watch_id = channel.add_watch_full (
                Priority.DEFAULT,
                IOCondition.IN | IOCondition.ERR | IOCondition.HUP | IOCondition.NVAL,
                on_ready);
            if (_watch_id == 0) {
                _creation_error = "could not attach the timer descriptor to the main loop";
                retention_timer_close (_fd);
                _fd = -1;
                _channel = null;
            }
        }

        public bool arm (int64 deadline_usec, out string ?error_message) {
            if (_shutdown || _fd < 0 || _watch_id == 0) {
                error_message = _creation_error ?? "timer scheduler is unavailable";
                return false;
            }

            int error_number;
            bool success = retention_timer_arm (_fd, deadline_usec, out error_number);
            error_message = success ? null : format_errno (error_number);
            return success;
        }

        public bool disarm (out string ?error_message) {
            if (_fd < 0) {
                error_message = _creation_error ?? "timer scheduler is unavailable";
                return false;
            }

            int error_number;
            bool success = retention_timer_disarm (_fd, out error_number);
            error_message = success ? null : format_errno (error_number);
            return success;
        }

        public void shutdown () {
            if (_shutdown) {
                return;
            }
            _shutdown = true;

            if (_watch_id != 0) {
                Source.remove (_watch_id);
                _watch_id = 0;
            }

            _channel = null;
            retention_timer_close (_fd);
            _fd = -1;
        }

        private bool on_ready (IOChannel channel, IOCondition condition) {
            if (_shutdown) {
                _watch_id = 0;
                return false;
            }

            if ((condition & (IOCondition.ERR | IOCondition.HUP | IOCondition.NVAL)) != 0) {
                return disable_after_error ("timer descriptor became unavailable");
            }

            bool consumed;
            int error_number;
            if (!retention_timer_read (_fd, out consumed, out error_number)) {
                return disable_after_error (format_errno (error_number));
            }

            if (consumed) {
                fired ();
            }
            return true;
        }

        private bool disable_after_error (string error_message) {
            _creation_error = error_message;
            _watch_id = 0;
            warning ("Notification history timer failed; retaining notification history: %s",
                     error_message);
            retention_timer_close (_fd);
            _fd = -1;
            _channel = null;
            return false;
        }
    }

    private string format_errno (int error_number) {
        return "%s (errno %d)".printf (retention_strerror (error_number), error_number);
    }

    private class RetainedEntry : Object {
        public uint32 id;
        public string revision;
        public uint8 urgency;
        public bool resident;
        public bool deferred;
        public bool has_receipt_time;
        public int64 received_at_usec;

        public RetainedEntry (uint32 id,
                              string revision,
                              uint8 urgency,
                              bool resident,
                              bool has_receipt_time,
                              int64 received_at_usec) {
            this.id = id;
            this.revision = revision;
            this.urgency = urgency;
            this.resident = resident;
            this.has_receipt_time = has_receipt_time;
            this.received_at_usec = received_at_usec;
        }
    }

    /** Tracks admitted notification history and expires it on a shared boot-time timer. */
    public class HistoryRetention : Object {
        private const int64 MICROSECONDS_PER_SECOND = 1000000;

        private HistoryRetentionClock _clock;
        private HistoryRetentionScheduler _scheduler;
        private HashMap<uint32, RetainedEntry> _entries = new HashMap<uint32, RetainedEntry> ();
        private HashMap<uint32, RetainedEntry> _dispatching
            = new HashMap<uint32, RetainedEntry> ();
        private int _ordinary_seconds = 0;
        private int _critical_seconds = 0;
        private ulong _scheduler_signal_id = 0;
        private bool _timer_armed = false;
        private bool _scheduler_ready = true;
        private bool _scheduler_warning_issued = false;
        private bool _clock_warning_issued = false;
        private bool _overflow_warning_issued = false;
        private bool _shutdown = false;

        public signal void expired (uint32 id, string revision);

        public HistoryRetention () {
            this.with_components (new BoottimeRetentionClock (),
                                  new TimerfdRetentionScheduler ());
        }

        internal HistoryRetention.with_components (HistoryRetentionClock clock,
                                                   HistoryRetentionScheduler scheduler) {
            _clock = clock;
            _scheduler = scheduler;
            _scheduler_signal_id = _scheduler.fired.connect (on_scheduler_fired);
        }

        /** Configures ordinary and critical history lifetimes in seconds; zero means unlimited. */
        public void configure (int ordinary_seconds, int critical_seconds) {
            if (_shutdown) {
                return;
            }

            restore_dispatching_entries ();
            _ordinary_seconds = normalize_limit (ordinary_seconds, "history-retention");
            _critical_seconds = normalize_limit (
                critical_seconds, "history-retention-critical");
            reschedule ();
        }

        /** Records a newly admitted or replaced notification using its receipt age. */
        public void track (uint32 id, string revision, uint8 urgency, bool resident) {
            if (_shutdown) {
                return;
            }

            int64 now_usec = 0;
            string ?error_message;
            bool has_receipt_time = _clock.read (out now_usec, out error_message);
            if (has_receipt_time) {
                _clock_warning_issued = false;
            } else {
                report_clock_failure (error_message);
            }

            _dispatching.unset (id);
            _entries.set (id, new RetainedEntry (id,
                                                 revision,
                                                 urgency,
                                                 resident,
                                                 has_receipt_time,
                                                 now_usec));
            reschedule ();
        }

        /** Defers expiry while the matching notification has an active inline reply. */
        public void set_deferred (uint32 id, string revision, bool deferred) {
            if (_shutdown) {
                return;
            }

            RetainedEntry ?entry = _entries.get (id);
            bool restored = false;
            if (entry == null) {
                RetainedEntry ?pending = _dispatching.get (id);
                if (pending != null && pending.revision == revision) {
                    _dispatching.unset (id);
                    _entries.set (id, pending);
                    entry = pending;
                    restored = true;
                }
            }

            if (entry == null || entry.revision != revision
                || (entry.deferred == deferred && !restored)) {
                return;
            }

            entry.deferred = deferred;
            reschedule ();
        }

        /** Removes an entry, optionally only when its current revision matches. */
        public void forget (uint32 id, string ?revision = null) {
            if (_shutdown) {
                return;
            }

            bool changed = false;
            RetainedEntry ?entry = _entries.get (id);
            if (entry != null && (revision == null || entry.revision == revision)) {
                _entries.unset (id);
                changed = true;
            }

            RetainedEntry ?pending = _dispatching.get (id);
            if (pending != null && (revision == null || pending.revision == revision)) {
                _dispatching.unset (id);
                changed = true;
            }

            if (changed) {
                reschedule ();
            }
        }

        /** Clears all tracked history without emitting expiry signals. */
        public void clear () {
            if (_shutdown) {
                return;
            }

            _entries.clear ();
            _dispatching.clear ();
            reschedule ();
        }

        /** Stops the timer and discards all records. */
        public void shutdown () {
            if (_shutdown) {
                return;
            }

            _shutdown = true;
            _entries.clear ();
            _dispatching.clear ();
            if (_scheduler_signal_id != 0) {
                _scheduler.disconnect (_scheduler_signal_id);
                _scheduler_signal_id = 0;
            }
            _scheduler.shutdown ();
            _timer_armed = false;
        }

        private int normalize_limit (int seconds, string property_name) {
            if (seconds < 0) {
                warning ("%s must be at least 0 seconds; using 0 (unlimited)", property_name);
                return 0;
            }
            return seconds;
        }

        private int seconds_for (RetainedEntry entry) {
            return entry.urgency == 2 ? _critical_seconds : _ordinary_seconds;
        }

        private bool deadline_for (RetainedEntry entry, out int64 deadline_usec) {
            deadline_usec = 0;
            int seconds = seconds_for (entry);
            if (entry.resident || entry.deferred || !entry.has_receipt_time || seconds == 0) {
                return false;
            }

            int64 duration_usec = ((int64) seconds) * MICROSECONDS_PER_SECOND;
            if (entry.received_at_usec > int64.MAX - duration_usec) {
                if (!_overflow_warning_issued) {
                    warning ("Notification history expiry deadline overflow; retaining the entry");
                    _overflow_warning_issued = true;
                }
                return false;
            }

            deadline_usec = entry.received_at_usec + duration_usec;
            return true;
        }

        private void reschedule () {
            if (_shutdown) {
                return;
            }

            bool has_deadline = false;
            int64 nearest_deadline = int64.MAX;
            foreach (RetainedEntry entry in _entries.values) {
                int64 deadline_usec;
                if (deadline_for (entry, out deadline_usec)
                    && (!has_deadline || deadline_usec < nearest_deadline)) {
                    nearest_deadline = deadline_usec;
                    has_deadline = true;
                }
            }

            if (has_deadline) {
                string ?error_message;
                bool success = _scheduler.arm (nearest_deadline, out error_message);
                _scheduler_ready = success;
                if (success) {
                    _timer_armed = true;
                    _scheduler_warning_issued = false;
                } else {
                    report_scheduler_failure (error_message);
                }
                return;
            }

            if (_timer_armed) {
                string ?error_message;
                bool success = _scheduler.disarm (out error_message);
                _scheduler_ready = success;
                if (success) {
                    _timer_armed = false;
                    _scheduler_warning_issued = false;
                } else {
                    report_scheduler_failure (error_message);
                }
            } else {
                _scheduler_ready = true;
            }
        }

        private void restore_dispatching_entries () {
            if (_dispatching.is_empty) {
                return;
            }

            ArrayList<RetainedEntry> pending = new ArrayList<RetainedEntry> ();
            foreach (RetainedEntry entry in _dispatching.values) {
                pending.add (entry);
            }
            _dispatching.clear ();

            foreach (RetainedEntry entry in pending) {
                if (!_entries.has_key (entry.id)) {
                    _entries.set (entry.id, entry);
                }
            }
        }

        private void on_scheduler_fired () {
            if (_shutdown) {
                return;
            }

            _timer_armed = false;
            if (!_scheduler_ready) {
                return;
            }

            dispatch_due ();
        }

        private void dispatch_due () {
            int64 now_usec;
            string ?clock_error;
            if (!_clock.read (out now_usec, out clock_error)) {
                report_clock_failure (clock_error);
                _scheduler_ready = false;
                string ?disarm_error;
                if (!_scheduler.disarm (out disarm_error)) {
                    report_scheduler_failure (disarm_error);
                }
                return;
            }
            _clock_warning_issued = false;

            ArrayList<RetainedEntry> due = new ArrayList<RetainedEntry> ();
            foreach (RetainedEntry entry in _entries.values) {
                int64 deadline_usec;
                if (deadline_for (entry, out deadline_usec) && deadline_usec <= now_usec) {
                    due.add (entry);
                }
            }

            foreach (RetainedEntry entry in due) {
                RetainedEntry ?current = _entries.get (entry.id);
                if (current == entry) {
                    _entries.unset (entry.id);
                    _dispatching.set (entry.id, entry);
                }
            }

            reschedule ();

            foreach (RetainedEntry entry in due) {
                if (_dispatching.get (entry.id) != entry) {
                    continue;
                }
                _dispatching.unset (entry.id);
                expired (entry.id, entry.revision);
            }
        }

        private void report_clock_failure (string ?error_message) {
            if (_clock_warning_issued) {
                return;
            }
            warning ("Could not read boot time for notification history; retaining entries%s",
                     error_message == null ? "" : ": %s".printf (error_message));
            _clock_warning_issued = true;
        }

        private void report_scheduler_failure (string ?error_message) {
            if (_scheduler_warning_issued) {
                return;
            }
            warning ("Notification history timer unavailable; retaining entries%s",
                     error_message == null ? "" : ": %s".printf (error_message));
            _scheduler_warning_issued = true;
        }
    }
}

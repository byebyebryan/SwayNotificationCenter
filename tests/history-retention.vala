using Gee;
using SwayNotificationCenter;

private class FakeRetentionClock : Object, HistoryRetentionClock {
    public int64 time_usec = 0;
    public bool available = true;

    public bool read (out int64 now_usec, out string ?error_message) {
        now_usec = time_usec;
        error_message = available ? null : "fake clock unavailable";
        return available;
    }
}

private class FakeRetentionScheduler : Object, HistoryRetentionScheduler {
    public bool fail_arm = false;
    public bool fail_disarm = false;
    public bool has_deadline = false;
    public int64 deadline_usec = 0;
    public bool stopped = false;

    public bool arm (int64 deadline_usec, out string ?error_message) {
        if (stopped || fail_arm) {
            error_message = "fake timer arm failed";
            return false;
        }

        this.deadline_usec = deadline_usec;
        has_deadline = true;
        error_message = null;
        return true;
    }

    public bool disarm (out string ?error_message) {
        if (stopped || fail_disarm) {
            error_message = "fake timer disarm failed";
            return false;
        }

        has_deadline = false;
        error_message = null;
        return true;
    }

    public void shutdown () {
        stopped = true;
        has_deadline = false;
    }

    public void fire () {
        has_deadline = false;
        fired ();
    }
}

private class RetentionFixture : Object {
    public FakeRetentionClock clock = new FakeRetentionClock ();
    public FakeRetentionScheduler scheduler = new FakeRetentionScheduler ();
    public HistoryRetention retention;

    public RetentionFixture () {
        retention = new HistoryRetention.with_components (clock, scheduler);
    }
}

void test_urgency_deadlines () {
    var fixture = new RetentionFixture ();
    var expired = new ArrayList<string> ();
    fixture.retention.expired.connect ((id, revision) => {
        expired.add ("%u:%s".printf (id, revision));
    });

    fixture.retention.configure (10, 2);
    fixture.retention.track (1, "low", 0, false);
    fixture.retention.track (2, "normal", 1, false);
    fixture.retention.track (3, "critical", 2, false);
    assert (fixture.scheduler.has_deadline);
    assert (fixture.scheduler.deadline_usec == 2000000);

    fixture.clock.time_usec = 2000000;
    fixture.scheduler.fire ();
    assert (expired.size == 1 && expired[0] == "3:critical");
    assert (fixture.scheduler.has_deadline);
    assert (fixture.scheduler.deadline_usec == 10000000);

    fixture.clock.time_usec = 10000000;
    fixture.scheduler.fire ();
    assert (expired.size == 3);
    assert (expired.contains ("1:low") && expired.contains ("2:normal"));
    fixture.retention.shutdown ();
}

void test_critical_unlimited_and_resident () {
    var fixture = new RetentionFixture ();
    var expired = new ArrayList<uint32> ();
    fixture.retention.expired.connect ((id, revision) => expired.add (id));

    fixture.retention.configure (1, 0);
    fixture.retention.track (10, "ordinary", 1, false);
    fixture.retention.track (11, "critical", 2, false);
    fixture.retention.track (12, "resident", 1, true);
    fixture.clock.time_usec = 1000000;
    fixture.scheduler.fire ();
    assert (expired.size == 1 && expired[0] == 10);
    assert (!fixture.scheduler.has_deadline);

    fixture.clock.time_usec = 10000000;
    fixture.scheduler.fire ();
    assert (expired.size == 1);

    fixture.retention.configure (1, 2);
    assert (fixture.scheduler.has_deadline);
    assert (fixture.scheduler.deadline_usec == 2000000);
    fixture.scheduler.fire ();
    assert (expired.size == 2 && expired[1] == 11);
    fixture.retention.shutdown ();
}

void test_disabled_age_and_reload () {
    var fixture = new RetentionFixture ();
    var expired = new ArrayList<string> ();
    fixture.retention.expired.connect ((id, revision) => expired.add (revision));

    fixture.retention.configure (0, 0);
    fixture.retention.track (20, "backlog", 1, false);
    fixture.clock.time_usec = 4000000;
    fixture.retention.configure (5, 0);
    assert (fixture.scheduler.deadline_usec == 5000000);
    assert (expired.is_empty);

    fixture.clock.time_usec = 5000000;
    fixture.scheduler.fire ();
    assert (expired.size == 1 && expired[0] == "backlog");
    fixture.retention.configure (0, 0);
    fixture.retention.configure (5, 0);
    fixture.scheduler.fire ();
    assert (expired.size == 1);
    fixture.retention.shutdown ();
}

void test_replacement_resets_age () {
    var fixture = new RetentionFixture ();
    var expired = new ArrayList<string> ();
    fixture.retention.expired.connect ((id, revision) => expired.add (revision));

    fixture.retention.configure (5, 0);
    fixture.retention.track (30, "old", 1, false);
    fixture.clock.time_usec = 4000000;
    fixture.retention.track (30, "new", 1, false);
    assert (fixture.scheduler.deadline_usec == 9000000);

    fixture.clock.time_usec = 5000000;
    fixture.scheduler.fire ();
    assert (expired.is_empty);
    assert (fixture.scheduler.deadline_usec == 9000000);

    fixture.clock.time_usec = 9000000;
    fixture.scheduler.fire ();
    assert (expired.size == 1 && expired[0] == "new");
    fixture.retention.shutdown ();
}

void test_deferred_expiry () {
    var fixture = new RetentionFixture ();
    var expired = new ArrayList<string> ();
    fixture.retention.expired.connect ((id, revision) => expired.add (revision));

    fixture.retention.configure (5, 0);
    fixture.retention.track (40, "reply", 1, false);
    fixture.retention.set_deferred (40, "reply", true);
    assert (!fixture.scheduler.has_deadline);

    fixture.clock.time_usec = 6000000;
    fixture.scheduler.fire ();
    assert (expired.is_empty);

    fixture.retention.set_deferred (40, "reply", false);
    assert (expired.is_empty);
    assert (fixture.scheduler.has_deadline && fixture.scheduler.deadline_usec == 5000000);
    fixture.scheduler.fire ();
    assert (expired.size == 1 && expired[0] == "reply");
    fixture.retention.shutdown ();
}

void test_reentrant_policy_extension () {
    var fixture = new RetentionFixture ();
    var expired = new ArrayList<uint32> ();
    fixture.retention.expired.connect ((id, revision) => {
        expired.add (id);
        if (expired.size == 1) {
            fixture.retention.configure (10, 10);
        }
    });

    fixture.retention.configure (1, 0);
    fixture.retention.track (50, "first", 1, false);
    fixture.retention.track (51, "later", 1, false);
    fixture.clock.time_usec = 1000000;
    fixture.scheduler.fire ();
    assert (expired.size == 1);
    assert (fixture.scheduler.has_deadline && fixture.scheduler.deadline_usec == 10000000);

    fixture.clock.time_usec = 9999999;
    fixture.scheduler.fire ();
    assert (expired.size == 1);
    fixture.clock.time_usec = 10000000;
    fixture.scheduler.fire ();
    assert (expired.size == 2);
    fixture.retention.shutdown ();
}

void test_reentrant_disable_preserves_age () {
    var fixture = new RetentionFixture ();
    var expired = new ArrayList<uint32> ();
    fixture.retention.expired.connect ((id, revision) => {
        expired.add (id);
        if (expired.size == 1) {
            fixture.retention.configure (0, 0);
        }
    });

    fixture.retention.configure (1, 0);
    fixture.retention.track (60, "first", 1, false);
    fixture.retention.track (61, "later", 1, false);
    fixture.clock.time_usec = 1000000;
    fixture.scheduler.fire ();
    assert (expired.size == 1 && !fixture.scheduler.has_deadline);

    fixture.retention.configure (1, 0);
    assert (expired.size == 1);
    assert (fixture.scheduler.deadline_usec == 1000000);
    fixture.scheduler.fire ();
    assert (expired.size == 2);
    fixture.retention.shutdown ();
}

void test_reentrant_defer_later_due_entry () {
    var fixture = new RetentionFixture ();
    var expired = new ArrayList<uint32> ();
    uint32 deferred_id = 0;
    fixture.retention.expired.connect ((id, revision) => {
        expired.add (id);
        if (deferred_id == 0) {
            deferred_id = id == 70 ? 71 : 70;
            fixture.retention.set_deferred (
                deferred_id, deferred_id == 70 ? "first" : "later", true);
        }
    });

    fixture.retention.configure (1, 0);
    fixture.retention.track (70, "first", 1, false);
    fixture.retention.track (71, "later", 1, false);
    fixture.clock.time_usec = 1000000;
    fixture.scheduler.fire ();
    assert (expired.size == 1);
    assert (!fixture.scheduler.has_deadline);

    fixture.clock.time_usec = 6000000;
    fixture.scheduler.fire ();
    assert (expired.size == 1);
    fixture.retention.set_deferred (
        deferred_id, deferred_id == 70 ? "first" : "later", false);
    assert (expired.size == 1);
    assert (fixture.scheduler.has_deadline && fixture.scheduler.deadline_usec == 1000000);
    fixture.scheduler.fire ();
    assert (expired.size == 2 && expired[1] == deferred_id);
    fixture.retention.shutdown ();
}

void test_clock_failure_at_dispatch_retains_and_recovers () {
    var fixture = new RetentionFixture ();
    var expired = new ArrayList<string> ();
    fixture.retention.expired.connect ((id, revision) => expired.add (revision));

    fixture.retention.configure (1, 0);
    fixture.retention.track (90, "known-age", 1, false);
    fixture.clock.time_usec = 1000000;
    fixture.clock.available = false;
    Test.expect_message ("swaync", LogLevelFlags.LEVEL_WARNING,
                         "*Could not read boot time*retaining entries*");
    fixture.scheduler.fire ();
    Test.assert_expected_messages ();
    assert (expired.is_empty && !fixture.scheduler.has_deadline);

    fixture.clock.available = true;
    fixture.retention.configure (1, 0);
    assert (fixture.scheduler.has_deadline && fixture.scheduler.deadline_usec == 1000000);
    fixture.scheduler.fire ();
    assert (expired.size == 1 && expired[0] == "known-age");
    fixture.retention.shutdown ();
}

void test_track_clock_failure_never_invents_age () {
    var fixture = new RetentionFixture ();
    var expired = new ArrayList<string> ();
    fixture.retention.expired.connect ((id, revision) => expired.add (revision));

    fixture.retention.configure (1, 0);
    fixture.clock.available = false;
    Test.expect_message ("swaync", LogLevelFlags.LEVEL_WARNING,
                         "*Could not read boot time*retaining entries*");
    fixture.retention.track (91, "unknown-age", 1, false);
    Test.assert_expected_messages ();
    assert (!fixture.scheduler.has_deadline);

    fixture.clock.available = true;
    fixture.clock.time_usec = 100000000;
    fixture.retention.configure (1, 0);
    fixture.scheduler.fire ();
    assert (expired.is_empty && !fixture.scheduler.has_deadline);

    fixture.retention.track (91, "fresh-age", 1, false);
    assert (fixture.scheduler.deadline_usec == 101000000);
    fixture.clock.time_usec = 101000000;
    fixture.scheduler.fire ();
    assert (expired.size == 1 && expired[0] == "fresh-age");
    fixture.retention.shutdown ();
}

void test_large_elapsed_jump_expires () {
    var fixture = new RetentionFixture ();
    var expired = new ArrayList<string> ();
    fixture.retention.expired.connect ((id, revision) => expired.add (revision));

    fixture.clock.time_usec = 5000000;
    fixture.retention.configure (2, 0);
    fixture.retention.track (92, "slept", 1, false);
    fixture.clock.time_usec = 14405000000;
    fixture.scheduler.fire ();
    assert (expired.size == 1 && expired[0] == "slept");
    fixture.retention.shutdown ();
}

void test_deadline_overflow_retains () {
    var fixture = new RetentionFixture ();
    uint expirations = 0;
    fixture.retention.expired.connect ((id, revision) => expirations++);

    fixture.clock.time_usec = int64.MAX - 10;
    fixture.retention.configure (1, 0);
    Test.expect_message ("swaync", LogLevelFlags.LEVEL_WARNING,
                         "*deadline overflow*retaining the entry*");
    fixture.retention.track (93, "overflow", 1, false);
    Test.assert_expected_messages ();
    assert (!fixture.scheduler.has_deadline);
    fixture.scheduler.fire ();
    assert (expirations == 0);
    fixture.retention.shutdown ();
}

void test_forget_clear_shutdown_ignore_stale_timer () {
    var fixture = new RetentionFixture ();
    uint expirations = 0;
    fixture.retention.expired.connect ((id, revision) => expirations++);
    fixture.retention.configure (1, 0);

    fixture.retention.track (94, "current", 1, false);
    fixture.retention.forget (94, "stale");
    fixture.clock.time_usec = 1000000;
    fixture.scheduler.fire ();
    assert (expirations == 1);

    fixture.retention.track (941, "forgotten", 1, false);
    fixture.retention.forget (941, "forgotten");
    fixture.scheduler.fire ();
    assert (expirations == 1);

    fixture.retention.track (95, "clear", 1, false);
    fixture.retention.clear ();
    fixture.scheduler.fire ();
    assert (expirations == 1);

    fixture.retention.track (96, "shutdown", 1, false);
    fixture.retention.shutdown ();
    fixture.scheduler.fire ();
    assert (expirations == 1);
}

void test_reentrant_replacement_of_later_due_entry () {
    var fixture = new RetentionFixture ();
    var expired = new ArrayList<string> ();
    uint32 replacement_id = 0;
    fixture.retention.expired.connect ((id, revision) => {
        expired.add ("%u:%s".printf (id, revision));
        if (replacement_id == 0) {
            replacement_id = id == 97 ? 98 : 97;
            fixture.retention.track (replacement_id, "replacement", 1, false);
        }
    });

    fixture.retention.configure (1, 0);
    fixture.retention.track (97, "first", 1, false);
    fixture.retention.track (98, "later", 1, false);
    fixture.clock.time_usec = 1000000;
    fixture.scheduler.fire ();
    assert (expired.size == 1);
    assert (fixture.scheduler.has_deadline && fixture.scheduler.deadline_usec == 2000000);

    fixture.clock.time_usec = 1999999;
    fixture.scheduler.fire ();
    assert (expired.size == 1);
    fixture.clock.time_usec = 2000000;
    fixture.scheduler.fire ();
    assert (expired.size == 2);
    assert (expired[1] == "%u:replacement".printf (replacement_id));
    fixture.retention.shutdown ();
}

void test_invalid_limits_and_scheduler_failure () {
    var fixture = new RetentionFixture ();
    uint expirations = 0;
    fixture.retention.expired.connect ((id, revision) => expirations++);
    Test.expect_message ("swaync", LogLevelFlags.LEVEL_WARNING,
                         "*history-retention*at least 0*");
    Test.expect_message ("swaync", LogLevelFlags.LEVEL_WARNING,
                         "*history-retention-critical*at least 0*");
    fixture.retention.configure (-1, -2);
    Test.assert_expected_messages ();
    assert (!fixture.scheduler.has_deadline);

    fixture.scheduler.fail_arm = true;
    Test.expect_message ("swaync", LogLevelFlags.LEVEL_WARNING,
                         "*timer unavailable; retaining entries*");
    fixture.retention.configure (1, 0);
    fixture.retention.track (80, "kept", 1, false);
    Test.assert_expected_messages ();
    fixture.clock.time_usec = 1000000;
    fixture.scheduler.fire ();
    assert (expirations == 0);
    fixture.scheduler.fail_arm = false;
    fixture.retention.configure (1, 0);
    fixture.scheduler.fire ();
    assert (expirations == 1);
    fixture.retention.shutdown ();
}

int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/history-retention/urgency-deadlines", test_urgency_deadlines);
    Test.add_func ("/history-retention/critical-unlimited-resident",
                   test_critical_unlimited_and_resident);
    Test.add_func ("/history-retention/disabled-age-reload", test_disabled_age_and_reload);
    Test.add_func ("/history-retention/replacement-resets-age", test_replacement_resets_age);
    Test.add_func ("/history-retention/deferred-expiry", test_deferred_expiry);
    Test.add_func ("/history-retention/reentrant-policy-extension",
                   test_reentrant_policy_extension);
    Test.add_func ("/history-retention/reentrant-disable-preserves-age",
                   test_reentrant_disable_preserves_age);
    Test.add_func ("/history-retention/reentrant-defer-later-due-entry",
                   test_reentrant_defer_later_due_entry);
    Test.add_func ("/history-retention/clock-failure-dispatch-recovery",
                   test_clock_failure_at_dispatch_retains_and_recovers);
    Test.add_func ("/history-retention/clock-failure-at-track",
                   test_track_clock_failure_never_invents_age);
    Test.add_func ("/history-retention/large-elapsed-jump", test_large_elapsed_jump_expires);
    Test.add_func ("/history-retention/deadline-overflow", test_deadline_overflow_retains);
    Test.add_func ("/history-retention/stale-timer-handles",
                   test_forget_clear_shutdown_ignore_stale_timer);
    Test.add_func ("/history-retention/reentrant-later-replacement",
                   test_reentrant_replacement_of_later_due_entry);
    Test.add_func ("/history-retention/invalid-limits-scheduler-failure",
                   test_invalid_limits_and_scheduler_failure);
    return Test.run ();
}

"""History retention acceptance against the owned native daemon fixture."""

import json
import os
import time


def check_retention(*, call, notify, snapshot, invoke, pump, config, original_config, events, GLib):
    assert os.environ.get("SWAYNC_PRIVATE_ACTION_TEST") == "1"

    def count():
        return call("NotificationCount", "()", ())[0]

    def closed(nid):
        pump(0.02)
        return [args[1] for member, args in events if member == "NotificationClosed" and args[0] == nid]

    def wait_for(predicate, message):
        deadline = time.monotonic() + 4
        while time.monotonic() < deadline:
            if predicate():
                return
            pump(0.02)
        raise AssertionError(message)

    def policy(ordinary=0, critical=0, *, grouping=True, visibility=None):
        value = dict(original_config, **{
            "history-retention": ordinary, "history-retention-critical": critical,
            "notification-grouping": grouping, "hide-on-clear": True,
        })
        if visibility is not None:
            value["notification-visibility"] = visibility
        config.write_text(json.dumps(value))
        call("ReloadConfig", "()", ())
        pump(0.03)

    def clear():
        call("CloseAllNotifications", "()", ())
        call("SetVisibility", "(b)", (False,))
        call("SetDnd", "(b)", (False,))
        pump(0.03)
        assert count() == 0

    def caps():
        return call("GetCapabilities", "()", (), cc=False)[0]

    clear()
    policy()
    assert "persistence" in caps()
    unlimited = notify("retention disabled")
    unlimited_revision = snapshot(unlimited)["revision"]
    pump(1.15)
    assert snapshot(unlimited)["revision"] == unlimited_revision
    assert closed(unlimited) == []

    # Enabling retention must use the existing receipt age, not the reload time.
    policy(1)
    wait_for(lambda: not snapshot(unlimited), "enabling retention reset the old card's age")
    assert count() == 0 and closed(unlimited) == [1]
    assert invoke(unlimited, unlimited_revision) == "unavailable"
    assert "persistence" not in caps()

    # History count can reach zero while the longer-lived popup stays actionable.
    long_popup = notify("popup outlives history", timeout=5000)
    popup_revision = snapshot(long_popup)["revision"]
    wait_for(lambda: count() == 0, "history deadline did not remove its card")
    assert snapshot(long_popup)["revision"] == popup_revision
    assert closed(long_popup) == []
    assert invoke(long_popup, popup_revision) == "dispatched"
    assert closed(long_popup) == [2]

    natural = notify("popup expires after history", timeout=1800)
    wait_for(lambda: count() == 0, "history deadline did not precede popup expiry")
    assert snapshot(natural) and closed(natural) == []
    wait_for(lambda: not snapshot(natural), "popup expiry left a pruned notification alive")
    assert closed(natural) == [1]

    hidden = notify("hide pruned popup", timeout=5000)
    wait_for(lambda: count() == 0, "history deadline did not remove hidden test card")
    call("HideLatestNotifications", "(b)", (False,))
    wait_for(lambda: not snapshot(hidden), "hiding final popup did not close pruned notification")
    assert closed(hidden) == [1]

    sender_closed = notify("sender closes pruned popup", timeout=5000)
    wait_for(lambda: count() == 0, "history deadline did not remove sender-close card")
    call("CloseNotification", "(u)", (sender_closed,), cc=False)
    pump(0.1)
    assert closed(sender_closed) == [3]

    # The old deadline and action revision cannot affect an identical replacement.
    replacing = notify("retention replacement")
    old_revision = snapshot(replacing)["revision"]
    pump(0.6)
    assert notify("retention replacement", replace=replacing) == replacing
    new_revision = snapshot(replacing)["revision"]
    assert old_revision != new_revision
    pump(0.55)
    assert snapshot(replacing)["revision"] == new_revision
    assert invoke(replacing, old_revision) == "stale"
    wait_for(lambda: not snapshot(replacing), "replacement never reached its new deadline")
    assert closed(replacing) == [1]

    hint = {"synchronous": GLib.Variant("s", "retention-replacement")}
    first = notify("retention synchronous first", hints=hint)
    first_revision = snapshot(first)["revision"]
    pump(0.6)
    second = notify("retention synchronous second", hints=hint)
    assert second != first and invoke(first, first_revision) == "unavailable"
    pump(0.55)
    assert snapshot(second)
    wait_for(lambda: not snapshot(second), "synchronous replacement did not expire")
    assert closed(second) == [1]

    # Config reload can extend a pending deadline or stop it altogether.
    policy(1)
    extended = notify("extended retention")
    pump(0.6)
    policy(3)
    pump(0.6)
    assert snapshot(extended)
    policy()
    pump(0.15)
    assert snapshot(extended) and closed(extended) == []
    assert "persistence" in caps()
    clear()

    # With the sidebar open these are history-only, even for critical urgency.
    policy(1)
    call("SetDnd", "(b)", (True,))
    call("SetVisibility", "(b)", (True,))
    normal = notify("DND retention")
    critical = notify("critical retention disabled", hints={"urgency": GLib.Variant("y", 2)})
    resident = notify("resident retention exempt", hints={"resident": GLib.Variant("b", True)})
    wait_for(lambda: not snapshot(normal), "DND or open sidebar paused retention")
    assert snapshot(critical) and snapshot(resident)
    assert count() == 2 and call("GetVisibility", "()", ())[0]
    policy(1, 1)
    wait_for(lambda: not snapshot(critical), "critical duration did not apply to existing age")
    assert snapshot(resident) and count() == 1 and closed(critical) == [1]
    clear()
    assert closed(resident) == [2]

    for grouping in (False, True):
        policy(1, grouping=grouping)
        call("SetVisibility", "(b)", (True,))
        cards = [notify("group expiry one"), notify("group expiry two")]
        assert count() == 2
        wait_for(lambda: count() == 0, "grouped/ungrouped history counts did not drain")
        assert all(closed(nid) == [1] for nid in cards)
        assert call("GetVisibility", "()", ())[0], "automatic cleanup closed the sidebar"
        clear()

    # Honor effective visibility rules: MUTED can retain a transient hint.
    policy(1, visibility={"retention-muted": {"state": "muted", "summary": "muted retained"}})
    muted = notify("muted retained", hints={"transient": GLib.Variant("b", True)})
    transient = notify("ordinary transient", hints={"transient": GLib.Variant("b", True)})
    assert count() == 1
    wait_for(lambda: not snapshot(muted), "effective muted history did not age out")
    assert closed(muted) == [1] and closed(transient) == [1]
    assert count() == 0

    # Selective popup hiding must preserve an excluded critical popup and ID.
    policy(0, 1)
    critical_popup = notify("critical popup retained", hints={"urgency": GLib.Variant("y", 2)})
    ordinary_popup = notify("ordinary popup hidden by DND", timeout=5000)
    wait_for(lambda: count() == 1, "critical history duration did not prune its card")
    assert snapshot(critical_popup) and closed(critical_popup) == []
    call("SetDnd", "(b)", (True,))
    pump(0.1)
    assert snapshot(critical_popup), "selective popup hide lost an excluded live popup"
    assert snapshot(ordinary_popup), "DND removed ordinary history"
    assert closed(critical_popup) == []
    clear()
    assert closed(critical_popup) == [2]

    # A malformed limit must preserve history rather than becoming a deletion age.
    policy(-1)
    invalid = notify("invalid retention keeps history")
    pump(0.2)
    assert snapshot(invalid) and "persistence" in caps()
    clear()
    config.write_text(json.dumps(original_config))
    call("ReloadConfig", "()", ())
    print(json.dumps({"result": "passed", "proof": "notification history retention",
                      "checks": ["disabled default", "enable backlog", "popup independence",
                                 "natural and hidden popup closure", "sender close exactly once",
                                 "identical and synchronous replacement", "reload extension/disable",
                                 "DND/open sidebar", "critical/resident", "grouping/counts",
                                 "muted transient", "filtered popup removal", "invalid limit"]}))

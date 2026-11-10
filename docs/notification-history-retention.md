# Notification history retention

`history-retention` and `history-retention-critical` set maximum ages for
notifications retained in the control-center history. Both are integer seconds
and default to `0`, which means unlimited. Low and normal urgency use
`history-retention`. Critical urgency uses `history-retention-critical`
independently: a value of `0` means critical history is unlimited, even when the
ordinary limit is enabled. Values must be between `0` and `2147483647`.
Invalid negative, fractional, non-numeric, or out-of-range values warn and
disable only the affected limit by using `0`; other valid configuration values
still load. The schema declares the same integer range, and the daemon checks
input again when reading JSON.

Age starts when the daemon accepts a notification into effective control-center
history. An accepted replacement starts a new age for its new revision. A
notification that does not pass the existing history admission and visibility
rules is not added to retention. Transient notifications follow those same
effective visibility rules. Resident notifications are exempt.

The clock is monotonic and includes time spent suspended. Wall-clock changes do
not change an entry's age. Do Not Disturb, a closed sidebar, and notification
grouping do not pause history age. An active inline reply defers removal of its
entry; once focus leaves the reply controls, an overdue entry is scheduled for
cleanup on the main loop.

Reloading configuration recalculates deadlines from each entry's original
receipt age. Enabling a limit can therefore remove older entries immediately
after the reload. Disabling a limit stops future expiry but does not restore
entries that were already removed. Increasing a limit preserves the original
age rather than restarting it.

History expiry removes the control-center card. A still-visible popup remains
alive and actionable until its own popup lifecycle ends. The notification is
closed once both the history card and popup view are gone; if either view goes
away first, the other view can finish its lifecycle. Automatic cleanup does not
close the sidebar.

When either retention limit is nonzero, the daemon omits the D-Bus
`persistence` capability. Clients may cache previously advertised capabilities
across a configuration reload; the notification protocol has no standard
capability-change signal. With both limits set to zero, the capability follows
the daemon's normal behavior.

The limits are global durations. They do not track read state, impose a count
limit, or provide per-application policy.

## Validation

Run the complete private native/compositor gate with:

```sh
python3 tests/check-fork.py --compositor
```

To run only the focused private notification-history lifecycle cases:

```sh
python3 tests/notification-actions.py --binary build/src/swaync --retention-only
```

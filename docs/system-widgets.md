# Live system widgets

The fork adds two opt-in native GTK widgets. Add them to `widgets` and configure
their refresh intervals through `widget-config`:

```json
{
  "widgets": ["title", "dnd", "system-stats", "battery", "notifications"],
  "widget-config": {
    "system-stats": { "interval": 1 },
    "battery": { "interval": 5 }
  }
}
```

`system-stats` shows average reported CPU frequency, utilization between samples,
and used/total RAM in GiB with a percentage. RAM uses `MemTotal - MemAvailable`.
The first CPU usage value arrives after one interval; opening the panel never
sleeps to collect it. CPU guest counters are not double counted. Frequency uses
`/proc/cpuinfo` with a fallback to online CPUs' `scaling_cur_freq` readings.

`battery` shows each present system battery's state, percentage, charge/discharge
power, and approximate time remaining at its current rate. It reads Linux power
supply attributes directly and excludes device batteries. It hides itself when
no system battery exists. Power comes from `power_now`, falling back to
`current_now * voltage_now` with the micro-unit conversion. ETA pairs energy with
power, or charge with current. Charging requires a reported
`charge_control_end_threshold` and targets that limit; discharging targets empty.
Missing attributes, zero rates, paused charging and full batteries show `—`
where a value cannot be estimated. No battery controls or writes are provided.

Both widgets read asynchronously, allow only one sample at a time, and refresh
only while the control center is open. Closing or replacing a widget cancels its
reads and timer. Reloading configuration while open starts the replacement
widgets immediately. No subprocesses, extra daemons or runtime dependencies are
needed. Debug logging includes samples when `G_MESSAGES_DEBUG=swaync` is set.

Style `.widget-system-stats` and `.widget-battery`; their rows use `.metric-label`
and `.metric-value`. The default style uses tabular numerals and the existing
theme colors.

Run the data/fixture tests with `meson test -C build --print-errorlogs`. The
private compositor lifecycle check is `python tests/notification-actions.py
--binary build/src/swaync`; it also protects the fork's retained action behavior.

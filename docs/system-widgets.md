# Live system widgets

The fork adds an opt-in native GTK dashboard, standalone clock, and unified
information widget. Configure polling intervals and clock formats through
`widget-config`:

```json
{
  "control-center-width": 448,
  "widgets": ["clock", "dashboard", "title", "notifications"],
  "widget-config": {
    "clock": { "time-format": "%H:%M", "date-format": "%a, %b %-d" },
    "title": { "show-dnd": true },
    "system-stats": { "interval": 1 },
    "gpu": { "interval": 2 },
    "battery": { "interval": 5 }
  }
}
```

The clock shows bold local time in the first column and a short weekday/date
in the second column. The full date is
available in its tooltip. It refreshes immediately when the
panel opens and checks once per second while open, so time changes and date
rollovers appear promptly. Both format strings use GLib `DateTime.format`
directives; for example, `%I:%M:%S %p` shows 12-hour time with seconds.
Set `widget-config.title.show-dnd` to `true` to place a compact DND switch
beside the Notifications title and Clear All action. The switch keeps its full
Do Not Disturb tooltip and accessible label; the standalone `dnd` widget
remains available.

## Unified information surface

Add `information` to `widgets` to show local time, System, Connections, and
Battery inside one divided frame:

```json
{
  "control-center-width": 448,
  "widgets": ["information", "title", "notifications"],
  "widget-config": {
    "clock": { "time-format": "%H:%M", "date-format": "%a, %b %-d" },
    "system-stats": { "interval": 1 },
    "gpu": { "interval": 2 },
    "battery": { "interval": 5 }
  }
}
```

The composite reuses the existing clock, system-stats, GPU, NetworkManager,
BlueZ, and battery readers. Its clock has bold local time on the left and a
plain short date on the right. System meters show numeric CPU/RAM percentages
and a matching level bar, with frequency and used/total GiB below. GPU/VRAM
meters appear only for runtime-active NVIDIA devices. Unknown readings show an
unavailable placeholder and do not create a zero-valued bar.

Connections combines the primary NetworkManager link and up to two connected
Bluetooth devices per row. Ethernet shows an Ethernet symbol and name on the
left, with its IPv4 address on the right or IPv6 when IPv4 is unavailable.
Wi-Fi shows its SSID and signal glyph/percentage. Bluetooth symbols use BlueZ
`Device1.Icon` metadata where the active theme provides it, with a generic
Bluetooth fallback; device names have full tooltips and battery `0%` remains
distinct from an unreported battery. Additional devices can be expanded, and
the view resets to two when the panel closes. Empty Connections and Battery
sections disappear with their separators. Service readers continue while a
section is hidden and the panel is open, so the section can reappear.

Battery displays a battery symbol and bold charge percentage on the left, with
state on the right and the charge gauge below. A marker appears only for a
valid charge limit reported by the battery. Charging uses the success meter
color; discharging at 20% or below uses warning, and at 10% or below adds a
text and accessible low-battery cue. Existing PWR/ETA details appear only when
the battery is not resting on external power.

`information#NAME` applies the same suffix to its child configuration keys:
`clock#NAME`, `system-stats#NAME`, `gpu#NAME`, `network#NAME`,
`bluetooth#NAME`, and `battery#NAME`. The widget has no extra product settings.
Its stable classes are `.widget-information`, `.information-clock`,
`.information-section`, `.information-section-title`, and `.information-meter`.
Default styles define fallbacks for `--information-bg`,
`--information-border-color`, `--information-heading-color`,
`--information-meter-track`, `--information-meter-fill`,
`--information-meter-charging`, `--information-meter-warning`, and
`--information-meter-critical`; selected appearances may override these on
`.widget-information`.

The dashboard stacks full-width System, Network, Bluetooth and Battery cards.
Each card uses two internal columns: CPU beside RAM, with GPU beside VRAM on
the following row, battery Charge beside State above PWR beside ETA, Wi-Fi SSID
beside signal strength, and pairs of Bluetooth devices. Ethernet uses the first
half-width ETH/IP cell and leaves the second empty. A lone Bluetooth device
also keeps its cell at half width. Missing hardware cards hide. Volume and
notifications follow at full width.
Long network/device names ellipsize with full-name tooltips and separate
percentages. Each Bluetooth cell has a device name on the left and battery
percentage on the right (`—` when unreported). Bluetooth initially shows two
connected devices, with expandable overflow that resets when the panel closes.
Expanded devices fill further two-column rows. Percentages reserve two digits
with a figure space for single digits; tabular numerals keep their rendered
width stable from 0 through 99 without leading zeroes. 100% remains supported.

Tab and Shift+Tab traverse the whole panel. Focused dashboard buttons and volume
controls receive their native activation/navigation keys; notification-history
shortcuts apply while focus is in history. The existing D and Escape shortcuts
remain available outside editable fields.

System shows average reported CPU frequency, utilization between samples,
and used RAM in GiB with a percentage (total in its tooltip). RAM uses
`MemTotal - MemAvailable`.
The first CPU usage value arrives after one interval; opening the panel never
sleeps to collect it. CPU guest counters are not double counted. Frequency uses
`/proc/cpuinfo` with a fallback to online CPUs' `scaling_cur_freq` readings.

NVIDIA GPU/VRAM rows show graphics frequency, utilization, used VRAM and its
percentage. Each NVIDIA graphics device bound to the NVIDIA driver is identified
by PCI address. The reader checks cached sysfs `power/runtime_status` first;
only `active` allows a targeted `nvidia-smi` query and a visible GPU/VRAM row.
Inactive, suspended and missing GPUs hide their rows; queries that fail on an
active GPU show Unavailable. Cached-state checks continue while the open panel's
GPU row is hidden so it can reappear without waking the device. The check
reduces wakeups but cannot prevent a suspend/query race. The optional CLI has a
one-second timeout; closing the panel kills and reaps an in-flight query. Other GPU vendors are not
queried. No NVIDIA package is required on systems without that hardware.

Battery shows each present system battery's state, percentage, charge/discharge
power, and approximate time remaining at its current rate. It reads Linux power
supply attributes directly and excludes device batteries. It hides itself when
no system battery exists. Power comes from `power_now`, falling back to
`current_now * voltage_now` with the micro-unit conversion. ETA pairs energy with
power, or charge with current. Charging requires a reported
`charge_control_end_threshold` and targets that limit; discharging targets empty.
ETA uses `H:MM`, such as `10:00` while discharging or `2:00 to 80%` while
charging, with its approximation explained in the tooltip.
Missing attributes, zero rates, paused charging and full batteries show `—`
where a value cannot be estimated. In the dashboard, Charge and State form the
first row, with PWR and ETA below. The second row hides on external power when
the battery is Full or Not charging at its reported limit (including the
configured start/stop charge window). A zero start threshold selects the firmware
default and is not used as the lower bound of that window. Without a reported limit, Not charging
hides the row only at 100%. Charging, discharging and lower paused batteries
keep the row visible. Charging batteries display `Charging to 80%` for a
reported 80% limit, or `Charging` when the limit is unavailable. Resting
batteries display `Idle at 80%` for a reported
limit below 100%, or `Full` otherwise; the raw driver state remains in the
tooltip. No battery controls or writes are provided.

Network uses NetworkManager's ObjectManager snapshot and `PrimaryConnection`,
following the primary default link rather than any connected Wi-Fi adapter.
Ethernet displays `ETH` with the link's IPv4 address, falling back to IPv6;
Wi-Fi displays `WIFI` with the SSID and a separate Signal percentage. Other
primary link types use `NET` with their address. A missing primary link shows
Disconnected; a missing NetworkManager service hides the card. Long addresses
and SSIDs ellipsize with a full-value tooltip, including interface and address.
Bluetooth uses BlueZ's ObjectManager snapshot for connected device names and
Battery1 percentages when available, including zero. The Bluetooth card hides
when no devices are connected, retaining its subscriptions while the panel is
open so it can reappear on connection. Both subscribe to relevant
property, interface and service-owner changes while open, coalescing bursts into
one asynchronous snapshot. Missing services hide their cards; service restarts
are observed. They never activate those services or request wireless scans.

All reads are asynchronous. CPU/RAM, GPU and battery poll independently with at
most one sample in flight per reader, only while the control center is open.
Closing or replacing the dashboard cancels its reads, subprocess, timers and
network/Bluetooth subscriptions. Reloading configuration while open starts replacements
immediately. Opening clears CPU/RAM placeholders and hides battery and wireless
cards until their first fresh read completes; cached values from a previous
opening are not displayed. Cancelled system reads are treated as unavailable
without passing null values to numeric parsers. No extra background daemon is
needed. Debug logging includes samples
and subscription lifecycle when `G_MESSAGES_DEBUG=swaync` is set.

The original standalone `system-stats` and `battery` widgets remain supported;
their wider row formats and existing interval configuration are unchanged.

Style `.widget-dashboard .dashboard-card`, `.dashboard-card-title`,
`.metric-label` and `.metric-value`. Standalone widgets retain
`.widget-system-stats` and `.widget-battery`. The default style uses tabular
numerals and existing theme colors.

Run the data/fixture tests with `meson test -C build --print-errorlogs`. The
private compositor lifecycle check is `python tests/notification-actions.py
--binary build/src/swaync`; it also protects the fork's retained action behavior.
Add `--dashboard-screenshot /tmp/dashboard.png` to capture the private fixture
with a long SSID and multiple Bluetooth devices, plus an Ethernet variant in
`/tmp/dashboard-ethernet.png`. When the binary is in a Meson
build tree, the test uses that tree's compiled stylesheet.

For focused GTK keyboard/fresh-opening regressions, run
`meson compile -C build widget-interaction-test`, then
`python tests/widget-interactions.py --binary build/widget-interaction-test`.
This optional target compiles the real panel/widget sources with a test entry
point; it is not installed or built by normal package builds. The runner owns a
private D-Bus session and Xvfb display, uses memory-backed settings, and cannot
connect to the desktop system bus or audio server. It requires Xvfb and xauth.
The runner loads and checks the compiled stylesheet from that build tree. Add
`--screenshot /tmp/information.png` to save its deterministic native GTK
Information fixture, including the optional sections, device overflow, and
reported battery limit.

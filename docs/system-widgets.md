# Live system widgets

The fork adds an opt-in native GTK dashboard. Add it to `widgets` and configure
its polling intervals through `widget-config`:

```json
{
  "control-center-width": 448,
  "widgets": ["title", "dnd", "dashboard", "notifications"],
  "widget-config": {
    "system-stats": { "interval": 1 },
    "gpu": { "interval": 2 },
    "battery": { "interval": 5 }
  }
}
```

The dashboard stacks full-width System, Battery, Network and Bluetooth cards.
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
Missing attributes, zero rates, paused charging and full batteries show `—`
where a value cannot be estimated. In the dashboard, Charge and State form the
first row, with PWR and ETA below. The second row hides on external power when
the battery is Full or Not charging at its reported limit (including the
configured start/stop charge window). Without a reported limit, Not charging
hides the row only at 100%. Charging, discharging and lower paused batteries
keep the row visible. Resting batteries display `At limit 80%` for a reported
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
immediately. No extra background daemon is needed. Debug logging includes samples
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

# Actions for specific retained notifications

This fork exposes three methods on the existing
`org.erikreider.swaync.cc` interface at `/org/erikreider/swaync/cc`.
They work for an individual floating popup or an ordinary notification retained
in the control center after its popup expires.

| Method | Arguments | Result |
| --- | --- | --- |
| `GetNotification` | `u id` | `a{sv}` snapshot, or an empty dictionary when absent |
| `InvokeAction` | `u id, s revision, s action_key` | `s`: `dispatched`, `stale`, or `unavailable` |
| `InvokeActionWithToken` | `u id, s revision, s action_key, s activation_token` | Same checked result, forwarding a caller-supplied compositor token |

The snapshot contains `id` (`u`), `revision` (`s`), `app` (`s`), `summary` (`s`),
`body` (`s`), and `actions` (`as`, alternating action keys and labels). Metadata
uses the original Notify values. Images and arbitrary hints are not returned.

`revision` is an opaque UUID created for each Notify call, including identical
replacements. Clients must inspect the intended notification, retain that
revision, and supply it when invoking its exact action key. An unknown or closed
ID returns `unavailable`; a replaced revision returns `stale`. Missing actions
do not dismiss the notification, run scripts, or substitute another action.
There is no latest-notification fallback. The existing latest-popup methods
and desktop click behavior retain their action selection and token semantics.

The server checks revision and invokes the current widget's action in one GTK
main-loop turn. Dispatch uses the same action, activation-token helper, scripts,
and resident handling as a desktop click. A non-resident action closes its
notification; a resident action leaves it retained. A successful result means
the action was dispatched, and does not prove application/compositor focus.
Clients must never automatically retry an invocation after a lost reply.

An external UI can use `InvokeActionWithToken` to forward its compositor-issued
activation token. SwayNC emits it before `ActionInvoked`; the compositor validates
the token when the target application requests activation. Tokens are bounded to
4,096 bytes. Empty tokens use the existing GDK helper. Desktop clicks keep using
the existing GDK input-serial path. A device has no fresh GTK input serial: on
Niri its host can acquire a token through Niri's supported IPC spawn operation,
using a short-lived non-graphical relay, rather than weakening focus policy.

Pin requests to the notification server's unique D-Bus owner, and invalidate
cached snapshots when that owner changes. Numeric IDs are reused after daemon
restart; old revisions never authorize a new notification at the same ID.
Each Notify also captures its unique originating D-Bus connection using the
bus-supplied sender, never an application hint. Both `ActivationToken` and
`ActionInvoked` are directed to that connection, for desktop clicks and remote
Open alike. They are never broadcast. A surviving application may retain stale
numeric IDs across a daemon restart; it cannot receive another client's action
when those IDs are reused. Replacements take the current Notify sender, and a
missing origin never falls back to broadcasting. Ordinary subscribers therefore
cannot observe another client's actions; actual bus monitors remain independent.

Explicitly dismissed, sender-closed, and expired transient notifications cannot
be invoked. This API does not persist application callbacks across restarts.

## Native validation

Build the fork normally, then run the real daemon on a private D-Bus session
and a disposable Niri compositor nested inside Xvfb:

```sh
python3 tests/notification-actions.py --binary build/src/swaync
```

Requires Kitty, Niri, Xvfb, and Python GObject introspection. The harness has no service
activation directories, uses private configuration/runtime/state paths, and does
not touch the running desktop notifier or compositor. It tests an older expired
card with a newer popup present, exact/missing actions, identical and synchronous
replacement, explicit close, transient expiry, resident handling, and ID reuse
after server restart. An unrelated subscriber must receive no token or action;
an identical cross-client replacement must address only its new origin. Three
real Kitty processes then remain alive across a SwayNC restart: an old and a new
notification reuse numeric ID 1, but only the new origin may request focus.
This catches stale client mappings that a daemon-only restart test misses.
`--client-test COMMAND...` optionally runs another native
client against that same disposable server.

## Packaging

The Arch package in `packaging/arch/` pins a published source commit. Source
changes are not installed merely by rebuilding that unchanged pin. After the
action change is committed and published, advance `_commit`, its archive SHA256,
and `pkgrel` together, then build and validate that exact package. Retain the
previous package for rollback. Desktop focus and physical 349 Open acceptance
remain deployment checks.

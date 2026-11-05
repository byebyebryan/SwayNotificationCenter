# Bryan's SwayNC fork

This is a maintained fork of `ErikReider/SwayNotificationCenter`, not a new
notification daemon. Read [the maintenance guide](docs/fork-maintenance.md) for
the upstream baseline, downstream patch boundaries and release procedure.

Keep reusable widgets, readers and styles in their own files. Limit changes to
upstream-owned notification, activation and control-center code to the hooks
needed for the fork's documented contracts. Preserve upstream defaults and
legacy widget behavior. Keep personal host policy and appearance selection in
Niri Plus and chezmoi, outside this repository.

Use `rtk` for interactive shell commands. For native changes, run
`python tests/check-fork.py --compositor` through the normal tool environment.
It uses private displays, buses and owned test clients. Do not operate the
user's desktop or notification history as a substitute for those checks.
Run the existing formatter and lint checks for touched source too.

Keep source, package-recipe and managed-consumer revisions distinct. Build and
verify the exact published source archive before changing the package pin.
The selected source commit must never be replaced with a moving branch URL.
Preserve previous package artifacts and unrelated consumer changes during
deployment. Native fixture acceptance and physical-host acceptance are separate.

# Bryan's SwayNC fork

This is a maintained fork of `ErikReider/SwayNotificationCenter`, not a new
notification daemon. Read [the maintenance guide](docs/fork-maintenance.md) for
the upstream baseline, downstream patch boundaries and release procedure.

Follow the guide's [development history policy](docs/fork-maintenance.md#branches-and-development-history).
The selected maintained branch is `niri-plus`; use current `main` until the
[migration plan](docs/niri-plus-migration-plan.md) is complete. Keep incremental
development commits on a feature branch until the complete change is ready for
one squash-merged PR. If a whole development cycle should become one source
commit, keep that cycle off the maintained branch until the final squash.
Preserve shared development history with ordinary pushes. Never squash, rebase
or force-push published maintained commits or move release tags. Start a fresh
feature branch after each squash merge. Integrate upstream through a dedicated
merge PR that preserves upstream ancestry.

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
After a squash merge, qualify the exact resulting source SHA on the maintained
branch, then pin that SHA and its archive checksum in a separate recipe commit.
The selected source commit must never be replaced with a moving branch URL.
Preserve previous package artifacts and unrelated consumer changes during
deployment. Native fixture acceptance and physical-host acceptance are separate.

# Maintaining this fork

The aim is to carry a small, understandable downstream product on top of
SwayNC. New status widgets belong in fork-owned modules; notification and
activation changes need narrow integration points and regression coverage.

## Upstream baseline

Upstream is [ErikReider/SwayNotificationCenter](https://github.com/ErikReider/SwayNotificationCenter).
The last incorporated upstream commit is
[`b8017a4d1a53debdf0e8766628fb80357eae31e7`](https://github.com/ErikReider/SwayNotificationCenter/commit/b8017a4d1a53debdf0e8766628fb80357eae31e7).
It was still upstream `main` when checked on November 5, 2026. This is a
development-branch base with Meson version `0.12.6`, rather than the `v0.12.6`
release tag. Keep that distinction in package and release notes.

Use separate `origin` and `upstream` remotes. Fetching upstream is a read-only
refresh; selecting and integrating an upstream update is a separate change.
For a checkout with the upstream remote configured:

```sh
rtk proxy git fetch upstream main
rtk proxy git log --oneline HEAD..upstream/main
rtk proxy git diff --stat b8017a4d1a53debdf0e8766628fb80357eae31e7..HEAD
```

Update the recorded baseline when an upstream integration is accepted. Keep
feature commits separate from package-recipe and consumer-selection commits.
Avoid rewriting published history or reformatting unrelated upstream files.

## Downstream patch map

| Area | Ownership and integration boundary | Regression evidence |
| --- | --- | --- |
| Niri activation | Small GDK launch-context change in `src/xdg_activation.vala` | Originating-window activation in the private compositor |
| Retained notification actions | Notification identity/revision and D-Bus hooks in notification model, daemon and action dispatch | Retained/replaced cards, owner routing, notifier restart and ID reuse |
| Information and legacy status widgets | Fork-owned widget, reader and style files; factory, schema and control-center lifecycle hooks | Data suites, native GTK layout/keyboard checks, private NetworkManager/BlueZ and visibility tests |
| Clock and inline DND | Clock module and a small title-row/config extension | Formatting, switch binding, reload/removal and timer cleanup |
| Arch delivery | `packaging/arch/`; checksum-pinned source and a downstream package release number | Canonical recipe build, package metadata and installed binary/recipe receipts |
| Personal desktop policy | External Niri Plus appearance and private chezmoi selectors | Their own consumer and per-host deployment checks |

Prefer new files for new readers and presentation components. Reuse shared
formatters and polling/subscription lifetime helpers. A new optional widget
must not add background polling to a legacy widget. Generic fixes are good
candidates for a separate upstream contribution; personal selection and policy
stay downstream.

## One native check entrypoint

The [fork workflow](../.github/workflows/fork-checks.yml) runs the same command
on Arch that maintainers can run locally:

```sh
rtk proxy python tests/check-fork.py --compositor
```

The command configures a build if needed, builds the application and private
widget harness, runs the schema/data suites, and tests native GTK widgets on a
private X display and D-Bus session. `--compositor` also runs the information
and legacy notifier lifecycle/action checks on private Niri displays, including
owned Kitty clients. Without that flag, the GTK and data checks still run.
It does not install packages, touch the user's notifier, or use the active
graphical session. `--build-dir` and `--artifacts` select the build/capture paths.

Install the normal build dependencies plus `python`, `python-gobject`, `dbus`,
`xorg-server-xvfb` and `xorg-xauth`; the compositor checks also need `niri`,
`kitty`, Mesa software rendering and fonts. The workflow records its package
versions and uploads native captures and build/test logs. Existing upstream
build and lint workflows remain independent; the new workflow checks source,
tests and workflow changes without adding dependencies to the runtime package.

## An upstream update

1. Create a dedicated integration branch or worktree from the current fork.
   Review the upstream range against the recorded baseline before integrating.
2. Review upstream-owned hooks in activation, notification identity/actions,
   control-center routing, factory/schema and title. Resolve conflicts by
   preserving the documented behavior, rather than copying whole old files.
3. Run the native entrypoint plus the existing formatter/lint and package
   checks. Review current native captures against the selected design.
4. Record the accepted upstream commit, changed downstream patches and any
   changed dependency requirements. Release through the pinned recipe path.

Do not combine an upstream upgrade with a desktop policy or visual redesign;
keeping the changes separate makes regressions easier to identify and revert.

## A downstream release

1. Review and commit the source/tests/docs, and require the fork checks on that
   source revision. Push the immutable source before calculating its canonical
   GitHub archive hash.
2. Update `packaging/arch/PKGBUILD` with that full source commit and checksum.
   Bump `pkgrel` for a downstream update at the same upstream version, then
   commit the recipe separately.
3. Build the canonical recipe, publish the package, recipe and checksums, and
   verify anonymous downloads. Keep source, recipe, package and host receipts
   distinct; local builds can differ in archive metadata and compiler inputs.
4. Update the managed consumer's source/recipe tuple, inspect scoped diffs and
   recovery artifacts, and apply only reviewed targets. Record offline hosts as
   pending. Retain the previous packages and configuration for rollback.

Returning to upstream requires checking every selected fork contract, including
retained actions and the information panel. An activation fix alone is not
sufficient. Either qualify equivalent upstream features or retire the affected
consumer configuration and API callers explicitly before switching packages.

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

The fork's `main` is its maintained downstream branch; `upstream/main` is the
upstream refresh source. Base ongoing work on the current fork `main` in a
feature branch or worktree, then consolidate and review the branch before a
release. Preserve published commits and integrate changes forward without
rewriting published history. Keep a source or test change separate from the
commit that updates the canonical package recipe.

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
| Explicit system stylesheet | Respect custom/skip flags before resolving the installed default in `src/functions.vala` | The clean native compositor fixture runs without an installed SwayNC stylesheet |
| Arch delivery | `packaging/arch/`; checksum-pinned source and a downstream package release number | Canonical recipe build, package metadata and installed binary/recipe receipts |
| Personal desktop policy | External Niri Plus appearance and private chezmoi selectors | Their own consumer and per-host deployment checks |

Prefer new files for new readers and presentation components. Reuse shared
formatters and polling/subscription lifetime helpers. A new optional widget
must not add background polling to a legacy widget. Generic fixes are good
candidates for a separate upstream contribution; personal selection and policy
stay downstream.

A future feature branch may evaluate splitting reusable GPU, NetworkManager
and Bluetooth readers or widgets out of the legacy dashboard, with separate
compatibility and lifecycle evidence.

## Fork checks and platform compilation

The [fork workflow](../.github/workflows/fork-checks.yml) runs on every push to
`main`, pull request targeting `main`, and manual dispatch, without path
filters. It has three checks and an aggregate named `Fork required checks`:

- `native` runs the private source and widget checks below.
- `arch-recipe` runs `tests/check-arch-recipe.py` in a clean Arch container as a
  non-root user and builds the canonical `packaging/arch/PKGBUILD` against its
  pinned source archive.
- `policy` runs the standard-library policy negative cases and pinned
  actionlint v1.7.12 across workflow syntax and embedded shell:
  `go run github.com/rhysd/actionlint/cmd/actionlint@v1.7.12`.
- `Fork required checks` waits for all three jobs and reports failure if any
  prerequisite fails, is skipped, or is cancelled; the gate succeeds only when
  all three checks succeed.

The inherited `.github/workflows/PKGBUILD-build.yml` job is upstream-only:
`PKGBUILD-git` hardcodes `git checkout main` in `prepare()`, so it cannot
qualify this fork's pull-request source or pinned release recipe. Fork coverage
comes from the strict `native` current-checkout build and `arch-recipe` pinned
canonical package build.

The native job runs the same command on Arch that maintainers can run locally:

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
versions and uploads native captures and build/test logs. A globally installed
notifier or a previously used build is not a prerequisite.

The Arch recipe job is package-recipe acceptance for the source SHA and archive
checksum selected by `PKGBUILD`; it is distinct from compiling the current
checkout in `native`. The `ubuntu-build` job separately configures and compiles
the checkout on Ubuntu 26.04 LTS. It is additional source compilation coverage,
not canonical package or deployment acceptance.

The Fedora source build is strict when it runs. It runs by default only in
`ErikReider/SwayNotificationCenter`; this fork runs it only when the repository
variable `SWAYNC_ENABLE_FEDORA_CHECKS` is exactly `true`, including manual
dispatch. The Fedora COPR publisher runs only in the upstream repository and
does not publish releases from this fork.

The proposed branch-protection contexts are `Fork required checks`,
`ubuntu-build`, `vala-linting`, `uncrustify`, and `rpmlint`. The proposed
settings request body is the `branch_protection` member of
`tests/ci-policy.json`; it has not been applied. Workflows do not configure
repository settings: treat protection as
enforced only after the settings are applied and verified in GitHub. Hosted
check runs and release-readiness remain pending until the workflows and
candidate commits are published and their checks have completed.

Before release, the manual `fork-release-check.yml` workflow runs
`tests/check-release.py` as a read-only readiness check. It verifies the full
source commit pinned by the recipe, the required recipe checks, and the native
check for that pinned source. It does not publish a release. A passing source
check for the working tree cannot substitute for the pinned recipe and source
checks.
The readiness query is read-only against GitHub and writes its requested local
JSON report to the selected output path.

Run the verifier against the full recipe commit SHA and save its local report:

```sh
rtk proxy python3 tests/check-release.py --recipe-commit FULL_RECIPE_SHA \
  --output build/fork-release-readiness.json
```

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

1. Consolidate and review source/tests/docs on a feature branch. Run the fork
   checks for the candidate source revision. After publishing the branch, open
   a pull request to `main` and verify its hosted required checks before
   integrating the reviewed source. Confirm the exact source commit is
   published on `main`, then calculate its canonical GitHub archive hash.
2. Update `packaging/arch/PKGBUILD` with that full source commit and checksum.
   Bump `pkgrel` for a downstream update at the same upstream version, and
   keep the recipe update in a separate commit from the source change. Publish
   the recipe candidate for its checks.
3. Run the manual read-only release-readiness check on the exact candidate.
   Treat branch protection as part of release readiness only after confirming
   the repository actually requires the intended status contexts.
4. Build the canonical recipe, publish the package, recipe and checksums, and
   verify anonymous downloads. Keep source, recipe, package and host receipts
   distinct; local builds can differ in archive metadata and compiler inputs.
5. Update the managed consumer's source/recipe tuple, inspect scoped diffs and
   recovery artifacts, and apply only reviewed targets. Record offline hosts as
   pending. Retain the previous packages and configuration for rollback.

Historical release 17 keeps its original acceptance and is not retroactively
requalified under the new gate.

Returning to upstream requires checking every selected fork contract, including
retained actions and the information panel. An activation fix alone is not
sufficient. Either qualify equivalent upstream features or retire the affected
consumer configuration and API callers explicitly before switching packages.

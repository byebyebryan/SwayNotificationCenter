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

## Branches and development history

The selected maintained branch is `niri-plus`, named for the desktop project
this fork supports. The currently published default and maintained branch is
still `main`. Continue using `main` until the
[migration plan](niri-plus-migration-plan.md) records a verified cutover; the
branch name in that plan is a target, not an already completed migration.

After the cutover, branch roles are:

| Branch | Role |
| --- | --- |
| `origin/niri-plus` | Maintained downstream branch and GitHub default; reviewed changes advance it without rewriting its published history |
| `origin/main` | Preserved historical downstream line; keep its published tip and release history intact |
| `upstream/main` | Upstream refresh source, fetched through the separate `upstream` remote |
| `feature/<change>` | Incremental development and review for one change or development cycle |
| `release/<package-update>` | Separate canonical package-recipe update after the source commit is qualified |

### Incremental development and consolidation

1. Start a feature branch or worktree from the current maintained tip. Commit
   and push drafts, fixes and review changes as needed. Shared development
   branches can stay append-only; routine consolidation needs no force push.
2. Keep all work intended to become one source commit on that branch until it
   is ready. A whole development cycle can become one source commit if none of
   its pieces have already landed separately on the maintained branch. When a
   cycle needs several review PRs, target its development branch and reserve
   one final PR for integration into the maintained branch.
3. Review the complete diff and run the appropriate checks. If the maintained
   branch advances, merge it into the development branch, resolve conflicts
   and rerun affected checks. Keep the PR current with required protection.
4. Use **Squash and merge** for the final downstream feature PR. Give the new
   commit a title and description that explain the complete resulting change.
   The maintained branch gains one new commit; neither branch's existing
   commits need to be rewritten. Preserve any development refs needed for
   recovery or provenance.
5. Wait for hosted checks on the exact resulting maintained source commit
   before selecting it for a package. PR checks on a development or synthetic
   merge SHA do not establish acceptance of that resulting source SHA.
6. Start subsequent work on a fresh branch from the updated maintained tip.
   Continuing a branch after its squash merge can repeat already integrated
   commits in later PRs.

For example, a feature can have many development commits while the maintained
branch receives one source commit and one later package-recipe commit:

```text
feature/sidebar:  B -> c1 -> c2 -> c3
maintained:      A -> B -> S -> P
```

`S` contains the combined feature changes. `P` pins the exact published `S`
archive and checksum after its source checks succeed. These are separate
commits because the recipe records the already existing source commit.
Keep temporary preview builds separate from canonical release pins.

The consolidation boundary is **integration into the maintained branch**.
Once commits have landed there, combining them changes published ancestry.
Fix those commits with later commits or reverts; do not postpone consolidation
until after integration or rewrite the maintained branch before a release.
One source commit per development cycle is an option, not a requirement to
combine unrelated features or every change in a release.

Upstream integrations use a dedicated merge PR that preserves upstream
ancestry, as described below. Keep merge commits available for those updates;
a blanket linear-history requirement would prevent that workflow.

See GitHub's [pull request merge documentation](https://docs.github.com/en/pull-requests/reference/pull-request-merges#squash-and-merge-your-commits)
for squash behavior and the caution about reusing a squashed development branch.

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

The [fork workflow](../.github/workflows/fork-checks.yml) covers every push to
`main` or `niri-plus`, pull requests targeting either branch, and manual
dispatch, without path filters. This includes coverage for the selected
maintained branch before the default changes. It has three checks and an
aggregate named `Fork required checks`:

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

The branch-protection policy selects `Fork required checks`, `ubuntu-build`,
`vala-linting`, `uncrustify`, and `rpmlint`. Its settings request body is the
`branch_protection` member of `tests/ci-policy.json`. Apply the policy separately
after these contexts have been reported, and verify the live GitHub settings:

```sh
rtk proxy gh api repos/byebyebryan/SwayNotificationCenter/branches/main/protection
```

Workflows do not configure repository settings. A source policy or local test
result does not establish that protection is active or hosted checks passed.
Verify those boundaries for the exact published candidate commit before release.

Before release, the manual `fork-release-check.yml` workflow runs
`tests/check-release.py` as a read-only readiness check. It verifies the full
source commit pinned by the recipe, the required recipe checks, and the native
check for that pinned source. It does not publish a release. A passing source
check for the working tree cannot substitute for the pinned recipe and source
checks.

The verifier normally requires the pinned source to be an ancestor of the
candidate recipe. The branch migration has one narrow compatibility path for
the unchanged release-17 recipe: it must match the immutable historical recipe
contents and source/checksum pin, its source must be an ancestor of that
historical recipe, and the candidate must be a later descendant of the recorded
consolidated preview head. Exact candidate recipe checks and independent exact-source native
checks are still required. Changed or unrecognized legacy recipes fail; future
source releases retain the normal ancestry requirement. The
[migration plan](niri-plus-migration-plan.md) records the immutable anchors.
The readiness query is read-only against GitHub and writes its requested local
JSON report to the selected output path.

Run the verifier against the full recipe commit SHA and save its local report:

```sh
rtk proxy python3 tests/check-release.py --recipe-commit FULL_RECIPE_SHA \
  --output build/fork-release-readiness.json
```

## An upstream update

1. Create a dedicated integration branch or worktree from the current
   maintained tip. Review the upstream range against the recorded baseline,
   then merge the selected upstream revision into that integration branch.
2. Review upstream-owned hooks in activation, notification identity/actions,
   control-center routing, factory/schema and title. Resolve conflicts by
   preserving the documented behavior, rather than copying whole old files.
3. Run the native entrypoint plus the existing formatter/lint and package
   checks. Review current native captures against the selected design.
4. Integrate through a dedicated PR using a merge commit so upstream ancestry
   is retained. Do not squash upstream integrations or rebase the published
   maintained branch. Record the accepted upstream commit, changed downstream
   patches and any changed dependency requirements. Release through the pinned
   recipe path.

Do not combine an upstream upgrade with a desktop policy or visual redesign;
keeping the changes separate makes regressions easier to identify and revert.

## A downstream release

1. Develop and review source/tests/docs on a feature branch using the
   [development history policy](#branches-and-development-history). Keep all
   commits intended for one source change there until the final squash PR.
   Verify the PR's hosted required checks before integration into the current
   maintained branch (`main` until cutover, then `niri-plus`).
2. Wait for hosted checks on the exact resulting maintained source SHA.
   Confirm that immutable commit is published, then download, build and verify
   its exact canonical GitHub archive and calculate its checksum. A green PR
   head is not a substitute for this source commit's checks, and the recipe
   must not pin a temporary development SHA.
3. On a fresh package-update branch, update `packaging/arch/PKGBUILD` with that
   full source commit and checksum.
   Bump `pkgrel` for a downstream update at the same upstream version, and
   keep the recipe update in a separate commit from the source change. Publish
   the recipe candidate for its checks.
4. After integrating the package update, run the manual read-only
   release-readiness check on the exact resulting recipe commit.
   Treat branch protection as part of release readiness only after confirming
   the repository actually requires the intended status contexts.
5. Build the canonical recipe, publish the package, recipe and checksums, and
   verify anonymous downloads. Keep source, recipe, package and host receipts
   distinct; local builds can differ in archive metadata and compiler inputs.
6. Update the managed consumer's source/recipe tuple, inspect scoped diffs and
   recovery artifacts, and apply only reviewed targets. Record offline hosts as
   pending. Retain the previous packages and configuration for rollback.

Historical release 17 keeps its original acceptance and is not retroactively
requalified under the new gate.

Returning to upstream requires checking every selected fork contract, including
retained actions and the information panel. An activation fix alone is not
sufficient. Either qualify equivalent upstream features or retire the affected
consumer configuration and API callers explicitly before switching packages.

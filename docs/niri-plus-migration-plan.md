# Maintained branch migration record

Status: GitHub cutover verified on November 5, 2026, at
`2026-11-06T03:47:46Z` UTC. The maintained/default branch is `niri-plus`;
historical `main` is preserved read-only. This forward documentation change
records the completed cutover and follows the normal reviewed PR/check path.
The ongoing workflow lives in the
[maintenance guide](fork-maintenance.md#branches-and-development-history).

## Decisions

- Use `niri-plus` as the maintained downstream branch and GitHub default.
- Preserve published `main`, release tags, archives and consumer pins.
- Develop incrementally on feature branches. Squash the final PR for one
  complete change or development cycle into the maintained branch.
- Qualify the exact resulting source SHA, then pin its immutable archive and
  checksum in a separate canonical package-recipe commit.
- Merge upstream through dedicated integration PRs that retain upstream
  ancestry. Keep merge commits available alongside downstream squash merges.

This creates a new consolidated lineage while leaving every existing published
ref intact. It does not simplify the ancestry of existing `main` in place.

## Preserved baseline and local preview

| Evidence | Recorded value |
| --- | --- |
| Published `main` snapshot | `45edc43ac67d29c457a987b58cec1e5d6fdf2894` |
| Incorporated upstream baseline | `b8017a4d1a53debdf0e8766628fb80357eae31e7` |
| Local preview branch | `preview/consolidated-fork` |
| Local preview head | `ccbcdd97c3e9ce342d78e065f99a64f3ac87cc42` |
| Identical baseline/preview file tree | `4679331402f96ee68b34203084b881ee9315c14b` |
| Downstream commits before/after consolidation | 14 / 6 |
| Existing package | `swaync-bryan` `0.12.6-17` |
| Preserved release-17 recipe/tag commit | `c6eeafb4ded51afc0a5f9a3d092fb1d4a86d0662` |
| Preserved release-17 source commit | `3d4458262c23ac66820cbb7a63b171bab1053ae8` |

The six preview commits cover activation, retained actions, the original
dashboard, the unified information/clock/network widgets, Arch packaging, and
CI/release verification. Their final tree matches the published baseline.
Migration commit `d75e02357addbc4c044d6f08c6bb707fea1444e6` adds branch-aware
CI, release validation, regression cases and the development instructions.
That qualified candidate has seven downstream commits. This cutover record
follows as a separate reviewed documentation commit, preserving the published
migration candidate. The original six-commit tree comparison is evidence for the
consolidation, not a claim that later migration changes leave that tree intact.

The preview receipt is retained under
`/home/bryan/code/SwayNotificationCenter-clock/build/history-cleanup-20261105/`.
Recheck all heads, clean/dirty status, remote refs and recovery points before
implementation. If the published maintained tip has advanced, reconcile that
new work explicitly before using this recorded baseline.

## Verified cutover

The qualified migration commit is
[`d75e02357addbc4c044d6f08c6bb707fea1444e6`](https://github.com/byebyebryan/SwayNotificationCenter/commit/d75e02357addbc4c044d6f08c6bb707fea1444e6).
The historical `main` tip and all existing release tags were preserved.
`niri-plus` has the five required GitHub Actions checks with administrator
and up-to-date enforcement; force pushes and deletions are blocked. Merge
commits remain available for upstream integrations. Historical `main` has the
read-only lock enabled. Squash commit messages default to the PR title/body.

Validation and acceptance:

- All 34 policy regressions and pinned actionlint v1.7.12 passed.
- The [hosted fork checks](https://github.com/byebyebryan/SwayNotificationCenter/actions/runs/42158198716)
  passed source/native, canonical pinned Arch package, policy and aggregate jobs.
- [Ubuntu compilation](https://github.com/byebyebryan/SwayNotificationCenter/actions/runs/42158198635)
  and [all required lint checks](https://github.com/byebyebryan/SwayNotificationCenter/actions/runs/42158198687)
  passed on the exact migration commit.
- The [hosted release-readiness check](https://github.com/byebyebryan/SwayNotificationCenter/actions/runs/42158573749)
  passed from a clean checkout, reporting `historical-release-17` provenance
  with independently verified source and candidate recipe check results.
- The full private native entrypoint also passed in an owned Arch container.
  The application, styles and canonical package contents match historical
  `main`; desktop state was preserved.
- After cutover, a fresh anonymous clone with no branch argument selected
  `niri-plus`; its read-only release verifier also reported the candidate ready.
- Both immutable release-17 archives were downloaded anonymously and matched
  the original source and recipe archive SHA-256 pins. Existing consumer pins
  were preserved.

The Niri Plus maintenance/widget links were updated through
[documentation PR 1](https://github.com/byebyebryan/niri-plus/pull/1), merged as
`4672016e7cfe4f4631b67209636b0720e9068784`. Its site build, 1,332 local browser
assertions and hosted PR check passed; site publication has its own workflow.

Machine-readable receipts, before/after settings, private native logs/captures
and the original archive downloads are retained under
`/home/bryan/code/SwayNotificationCenter-clock/build/niri-plus-migration-20261105/`.
Final documentation/branch acceptance is verified after this record's normal
PR integration; those checks advance the branch without rewriting the
qualified migration commit.

## Implementation sequence

The procedure below is retained for the migration's review and rollback
context. The current branch state is recorded above; refresh evidence before
performing any further repository transition.

1. **Review and preserve.** Review the six commits for coherent source,
   packaging and CI boundaries. Reconfirm the exact tree comparison against the
   recorded published baseline. Record remote `main`, all release tags and the
   existing protection/settings so preservation and rollback are verifiable.
   Audit open PRs and any callers using moving branch links.
2. **Prepare the migration candidate locally.** Start from the consolidated
   preview. Carry only the reviewed documentation changes from
   `docs/niri-plus-workflow`; do not merge that branch or historical `main`
   into the candidate, which would bring the old development commits back.
   Add the CI and validation changes below as one focused migration commit.
   Review the candidate diff against the published baseline: application,
   styles and canonical package contents must still match it.
3. **Adapt branch-aware checks.** Add `niri-plus` to fork, Ubuntu, lint and
   opt-in Fedora source coverage while retaining upstream `main` support where
   applicable. Set `tests/ci-policy.json` to the selected maintained branch.
   Preserve required job names, strict failure handling and upstream-only
   publishing guards. Update the guide's current-state descriptions only when
   the corresponding cutover step has actually happened.
4. **Handle the preserved release-17 pin narrowly.** The verifier currently
   requires the pinned source to be an ancestor of every recipe commit. That
   source remains on preserved historical `main`, not the new consolidated
   lineage. Add a documented compatibility path only for the unchanged
   release-17 recipe: verify its canonical recipe contents and exact
   source/checksum tuple against the immutable historical recipe commit, and
   verify source ancestry within that historical release. Require fallback
   candidates to be later descendants of the consolidated preview head so an
   unrelated history copying the recipe cannot use the exception. Continue
   requiring exact candidate recipe checks and independent exact-source native
   checks.
   Keep the normal ancestry requirement for future source releases. Reject
   altered or unrecognized legacy tuples and missing/failed evidence. This
   preserves the old release's provenance without claiming it was originally
   qualified under the newer release gate.
5. **Validate locally, then publish the new branch.** Check documentation
   links and whitespace, policy regression cases and pinned actionlint. Add
   meaningful cases for the exact preserved recipe, altered recipe/source or
   checksum, unrelated history, and the future-release ancestry requirement.
   Publish `niri-plus` as a new branch using an ordinary push. Verify its exact
   head has passing native, canonical Arch package, Ubuntu and lint checks,
   then run the read-only release-readiness workflow on that head.
6. **Protect, then switch defaults.** Apply and verify the existing required
   checks and administrator enforcement on `niri-plus`, with force pushes and
   deletions blocked. Keep merge commits available for upstream integration.
   Change GitHub's default only after checks and protection are verified.
   Keep historical `main` at its recorded tip and freeze it against new work.
7. **Finish documentation and contributor handoff.** Update the Niri Plus
   maintenance/widget documentation links that currently point to `main`.
   Record the verified cutover and final SHA in this plan and update the
   maintenance guide and agent instructions to the actual current state.
   Use a normal reviewed documentation PR for that post-cutover record; do not
   amend or rewrite the published migration candidate to insert later evidence.
   Refresh the primary checkout's tracking configuration and remote default
   reference. Preserve sibling worktrees; port any still-needed changes from
   old branches into fresh branches without merging the historical line back
   into `niri-plus`.

The branch migration keeps the existing package identity and immutable
release-17 source/recipe/checksum pins. Package publication and desktop rollout
belong to a later release containing changes that require them.

## Acceptance and rollback

- A fresh clone selects `niri-plus`; new development branches start there.
- The final candidate has the required hosted checks and verified protection.
- Required CI runs for PRs targeting the maintained branch; upstream refresh
  and publishing guards retain their intended behavior.
- The exact preserved legacy recipe passes compatibility validation; altered
  legacy pins and invalid future ancestry fail.
- Published historical `main`, release tags, canonical recipe contents,
  consumer pins and existing archive downloads are preserved.
- Maintainer documentation, agent instructions and Niri Plus links agree on
  the branch roles and the squash/source/package sequence.

If qualification fails before cutover, keep `main` as the default and retain
the candidate for investigation. If the default must be restored afterward,
switch it back to preserved `main` and deliberately restore that branch's
ability to accept work. Keep the new branch for diagnosis and reconcile any
new work before resuming development. Neither rollback path requires force
pushing, deleting commits or moving release tags.

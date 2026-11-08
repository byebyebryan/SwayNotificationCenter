# Niri Plus reset record

The one-time clean reset was approved on November 7, 2026. This record captures
its construction and release gates. The
[`niri-plus-1` release receipt](https://github.com/byebyebryan/SwayNotificationCenter/releases/tag/niri-plus-1)
records the resulting recipe SHA, public cutover and package acceptance;
managed host rollout has independent consumer receipts.

## Intended lineage

The reset candidate starts at upstream development commit
[`b8017a4d1a53debdf0e8766628fb80357eae31e7`](https://github.com/ErikReider/SwayNotificationCenter/commit/b8017a4d1a53debdf0e8766628fb80357eae31e7)
(`U`) with the accepted downstream tree. The target is:

```text
main:       U                         pure upstream mirror
niri-plus:  U -> S -> P               maintained/default branch
                         ^
                    niri-plus-1       planned tag at P
```

`S` is the single downstream source baseline,
`7e0ea67572a5c98412572c1ef3eb6920354fa1d6`. Its anonymous archive has SHA-256
`aa54161e698a434f8b1b624b1cdbdc214d2516e56a708e31217dce4ccb413408`;
all 152 tracked files matched the published tree, all four Meson suites passed,
and all five required hosted contexts passed. Its `src/`, `data/`, `meson.build`
and manpage objects match the accepted pre-reset tree exactly. `P` is the
separate package-18 recipe commit after `S`, identified by the immutable
`niri-plus-1` release tag after recipe qualification. Its exact SHA belongs in
the release receipt rather than in a self-referential source file.

## Source and recipe gates

The accepted source tree keeps the package identity `swaync-bryan`, binary,
service, D-Bus interfaces, configuration paths and upstream licensing/history.
It does not introduce a package rename, epoch, upstream upgrade or runtime
change solely to enable the reset. The reset source preparation preserves the
accepted `src/`, `data/` and Meson runtime inputs; the final source receipt must
record the exact tree-identity check rather than infer it from this policy text.

`S` may retain the existing package release-17 pin temporarily as a build input
while the archived source remains available. That recipe is not release-ready
on the reset lineage: its pinned source is not an ancestor of `S`, so the strict
release check must reject it. After the exact `S` source has passed its hosted
checks and its immutable archive has been downloaded, inspected, built and
hashed, `P` can set `pkgrel` to 18 and pin that exact `S` SHA and measured
archive checksum. The release-readiness check for `P` requires normal
`source-ancestor` provenance, all five required recipe checks and the native
check for the exact pinned source.

The five recipe check contexts remain `Fork required checks`, `ubuntu-build`,
`vala-linting`, `uncrustify` and `rpmlint`. The aggregate retains its native
private-display, private-bus and owned-client fixtures plus the canonical Arch
recipe and policy jobs. Fork push and pull-request checks run only for
`niri-plus`; manual dispatch remains available to qualify exact SHAs on a
temporary reset branch. The upstream mirror does not receive downstream fork
checks.

## One-time reset and ongoing history policy

The approved cutover replaces the published `main` and `niri-plus` refs together
as one controlled, lease-checked operation. `main` becomes a pure upstream
mirror, locked between deliberate fast-forward syncs, with no downstream commits
or downstream check requirements. `niri-plus` remains the default and
maintained downstream branch. This single reset is the only
history-replacement exception; do not force-push `main` again after cutover.

After cutover, ordinary protected development resumes: make changes on feature
branches, use squash merges for complete downstream PRs, and never rewrite
published maintained commits or move release tags. Integrate upstream through
a dedicated merge PR that preserves upstream ancestry; keep merge commits
enabled for that purpose. See the [maintenance guide](fork-maintenance.md) for
the branch and release procedure.

## Completion evidence

The public acceptance receipt is the
[`niri-plus-1` release](https://github.com/byebyebryan/SwayNotificationCenter/releases/tag/niri-plus-1).
Its release notes and assets carry the exact `S`/`P` SHAs and release-readiness
receipt after publication; preparing this record alone does not publish them.

The final receipt records exact `U`, `S` and `P` SHAs; exact hosted check results;
source archive contents and checksum; canonical recipe build and package
metadata; branch/default/protection state; release and download hashes; and
separate consumer and host acceptance. Native fixtures, source archive,
canonical package, published release, managed consumer and physical hosts are
distinct acceptance boundaries. No cutover, release or host result is complete
until its corresponding evidence is recorded. Historical release artifacts
remain preserved through consumer migration and the separately reviewed cleanup
step.

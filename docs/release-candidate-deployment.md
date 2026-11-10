# Daily-use release candidates

RC deployment does not create a stable release or advance `niri-plus`. Commit
feature work on its development branch with ordinary pushes. Resolve that
branch's head once, qualify the exact source commit, and verify its anonymous
canonical archive before selecting it for a candidate package.

Create a separate `rc/<candidate>` branch from that source commit. Its recipe
commit changes `packaging/arch/PKGBUILD` only on the RC branch, pins the exact
source/archive checksum, and reserves a monotonically increasing package
revision. RC1 uses `0.12.6-19`; a later stable package must use a higher revision.
The package description and consumer channel identify it as an RC. No GitHub
release or tag is required. Never rewrite a published branch or move a tag.

The canonical package check can qualify a candidate recipe directly:

```sh
rtk proxy python tests/check-arch-recipe.py --recipe packaging/arch/PKGBUILD
```

Run hosted checks on the exact source and recipe commits. Preserve source
ancestry, build the pinned archive, check the package metadata and verify the
downloaded package hash. Keep the previous package for rollback. Source checks
on a development SHA do not qualify the eventual squash-merged stable source.

Chezmoi owns candidate admission and policy. Keep its stable tuple intact and
select the RC through a separate known-host allowlist, full source/recipe SHAs
and both archive checksums. Record the branch name as provenance only. Never
replace immutable archive URLs with a branch URL or silently update at boot.

Deploy only reviewed notifier targets. Remove an owned temporary preview
override only after candidate package/config preparation, then use the ordinary
packaged service so selection survives reboot. Retain rollback artifacts and
preserve native sessions, DND/sidebar state and unrelated host-local work.
Restarting SwayNC clears its in-memory notification history.

Keep incremental fixes on the feature branch during the soak. After daily-use
acceptance, squash-merge the complete source change, qualify the resulting
maintained source SHA, and create the separate stable recipe update described
in [the maintenance guide](fork-maintenance.md). A candidate does not satisfy
that stable-release procedure merely because its package checks pass.

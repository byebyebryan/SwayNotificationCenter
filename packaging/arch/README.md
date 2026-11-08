# Arch package for Bryan's SwayNC fork

`swaync-bryan` builds the checksum-pinned fork commit in `PKGBUILD`. It provides
`swaync` and conflicts with the upstream package while keeping the same binary,
service, D-Bus and configuration paths. Normal distribution upgrades cannot
replace it with the package named `swaync`.

The package builds the fork's source directly, including the input-serial fix
in `src/xdg_activation.vala`; it does not apply a separate downstream patch to
an upstream release. The reset source line starts at upstream development
commit `b8017a4`, rather than the `0.12.6` release tag.

The reset source commit `S` may retain the existing recipe-17 pin temporarily
as a build input while its archived source remains available. That pin is not
release-ready on the reset lineage because its source is not an ancestor of
`S`; the strict release check must reject it. After `S` is published, passes
its exact hosted checks, and its immutable source archive is inspected, built
and hashed, the separate recipe commit `P` can set `pkgrel` to 18 and pin that
exact `S` SHA and measured archive checksum. This is the intended sequence,
not a claim that package 18 or its release checks are complete.

## Build and install

Install Arch's `base-devel` and the recipe's runtime dependencies first, then
copy `PKGBUILD` to an empty temporary directory and run there as the ordinary
user. Preinstalling runtime dependencies keeps `--rmdeps` from removing them
before the separate package-install transaction. Chezmoi's package manifest
already does this for selected hosts.

The commands below retain the existing package-17 example. In source commit
`S`, building its recipe-17 pin is only a temporary source/build check, not a
release or rollout instruction. The install command names the preserved
package-17 artifact; it is not post-reset host acceptance. Update these
version-specific examples to package 18 in recipe commit `P`, after `S` has
been qualified.

```sh
rtk proxy makepkg --syncdeps --rmdeps --noconfirm
rtk proxy sudo pacman -U --noconfirm --ask=4 swaync-bryan-0.12.6-17-x86_64.pkg.tar.zst
rtk proxy systemctl --user restart swaync.service
```

`--ask=4` answers the declared conflict-removal question, allowing pacman to
remove `swaync` and install `swaync-bryan` in one transaction. It does not skip
dependency, checksum or file-conflict checks. `--rmdeps` removes dependencies
newly installed by makepkg after a successful build; pre-existing packages stay
installed. Retain the old package archive for recovery. A SwayNC restart clears
its in-memory notification history. Kitty, agent and compositor processes do
not need restarting.

Chezmoi selects the published recipe revision and source checksum independently
and builds outside its managed source tree. Its installer does nothing when
the selected package version and installed recipe stamp already match. The
development clone does not need to be present on a managed machine.

## Activation fix

The old helper committed an activation token without an input serial. Niri
26.04 treats that token as urgency-only, so a notification click marks Kitty
urgent without focusing its originating terminal. GTK's public
`Gdk.AppLaunchContext.get_startup_notify_id()` supplies the seat's most recent
input serial and handles the token lifecycle, with no new runtime dependency
or compositor focus-policy change.

On October 21, 2026, a stable-release backport first qualified this source change
on Starship. Local OSC 9 and SSH-delivered OSC 9 alerts both produced activation
and default-action signals on click, with nonzero input serials in Wayland
traces. Bryan confirmed that clicking focused the terminal. The separate
`swaync-bryan` package replaced that initial backport with a direct fork build.
This is historical evidence for the stable-release activation backport; it does
not qualify reset source `S`, recipe `P`, package 18 or any post-reset host
installation.

## Return to upstream

Qualify equivalents for every selected fork feature before switching packages:
the activation fix, retained-card action API, information widgets and their
configuration are independent contracts. An activation fix alone is not enough.
The [fork maintenance guide](../../docs/fork-maintenance.md) records their source
and regression boundaries. If a feature is retired instead, update its consumer
configuration and API callers along with the package owner so a later apply
does not reinstall the fork. Switching the desktop notifier to Mako alone
preserves the inactive SwayNC package for rollback.

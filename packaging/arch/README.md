# Arch package for Bryan's SwayNC fork

`swaync-bryan` builds the checksum-pinned fork commit in `PKGBUILD`. It provides
`swaync` and conflicts with the upstream package while keeping the same binary,
service, D-Bus and configuration paths. Normal distribution upgrades cannot
replace it with the package named `swaync`.

The package builds the fork's source directly, including the input-serial fix
in `src/xdg_activation.vala`; it does not apply a separate downstream patch to
an upstream release. The fork currently follows upstream's development branch
based on `b8017a4`, rather than the 0.12.6 release tag. Bump `pkgrel` when changing
the pinned source without changing `pkgver`, and update its archive checksum.

## Build and install

Install Arch's `base-devel`, copy `PKGBUILD` to an empty temporary directory,
then run there as the ordinary user:

```sh
rtk proxy makepkg --syncdeps --rmdeps --noconfirm
rtk proxy sudo pacman -U --noconfirm --ask=4 swaync-bryan-0.12.6-1-x86_64.pkg.tar.zst
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
`swaync-bryan` package replaces that initial backport with a direct fork build.

## Return to upstream

Once an upstream release includes an equivalent fix, remove `swaync-bryan` and
install `swaync` through pacman or yay. Change chezmoi's package owner at the
same time so a later apply does not reinstall the fork. Switching the desktop
notifier to Mako alone preserves the inactive SwayNC package for rollback.

The 349's selected-card Open action is a separate API feature and remains
disabled by the desktop configuration.

# renku-retina

HiDPI ("Retina") patches for RenkuOS, x86_64 and arm64. They apply to
RenkuOS/Source (`main` and `nightly` as of 2026-10-09) with `git apply`, and
ship as the package **R Retina** (`rretina`) on pkgman.rainygirl.com, so an
installed system gets them without a new image:

```sh
pkgman install rretina    # then reboot
pkgman uninstall rretina  # then reboot; the stock files are back
```

Haiku already scales almost everything by the default font size: controls,
spacing, window borders, scroll bars, menu and list icons, Deskbar, and the
mouse cursor all grow with it (`BControlLook::ComposeSpacing()` /
`ComposeIconSize()`, the decorator, `CursorManager`). What it gets wrong is
choosing that size on a HiDPI display, and keeping the desktop in order when
the size changes. These patches fix those two things.

| Patch | What it fixes |
| --- | --- |
| `0001-app-server-dpi-ui-scale` | With no font sizes chosen, app_server picked the UI scale from the resolution alone (x1.5 above 1920x1080, x2 above 3840x2160). It now uses the panel's pixel density from EDID: `dpi / 110`, in quarter steps from 1 to 3. A 27" 2560x1440 monitor stays at 1 (it got 1.5), a 13" 2560x1600 laptop panel gets 2 (it got 1.5), a 15" 4K panel 2.5. No EDID: the resolution rule as before, now inclusive of 3840x2160. The choice is logged to the syslog. |
| `0002-tracker-desktop-location-scale` | Desktop icon positions are saved in pixels, so after the scale grows the icons pile onto each other with overlapping labels. Tracker now records the scale the positions were saved under (`_trk/pinfo_scale` on the desktop directory) and scales them to the current one when it loads them. |
| `0003-ui-scale-setting` | Appearance's Fonts tab gets a "UI scale" menu: Automatic, 100%, 150%, 200%. The fixed choices size the four system fonts to 12, 18 and 24 pt. Automatic sizes them by the display (as 0001) and leaves `auto` in `~/config/settings/system/app_server/ui_scale`, so app_server re-picks the scale on every boot whatever sizes were saved. Changing a font size by hand ends Automatic; sizes matching no choice show as "Custom". |

## How the package works

`rretina` contains `servers/app_server`, `lib/libtracker.so` and
`preferences/Appearance`, the same paths the `haiku` package has. Where several packages provide one path,
packagefs shows a system package's file over another package's, and among
system packages the one with the newest modification time. `rretina` is
therefore flagged `system_package` and its two files are stamped when the
package is built. While it is installed they are the system's; removing it
brings the `haiku` package's files back at once, and a later `haiku` package
(newer files) would win over it. No install scripts, launch overrides or
packagefs settings are involved.

The binaries use private interfaces of `libbe` and `app_server`, so the
package requires the exact `haiku` version they were built for
(`r1~beta6_hrev60071_15_dirty`, RenkuOS `nightly` 47367b99ab). Build it with
`package/make-rretina.sh <arch> <haiku version>` from `dist/<arch>/`.

Two other routes were tried and dropped:
- Install scripts that copy the binaries to the non-packaged directories,
  hide the system libtracker with `BlockedEntries` and redirect the
  app_server launch job. Removing that package left the redirection in
  place: package_daemon moves a package file away before it runs the
  package's pre-uninstall scripts, so they cannot be read and never run
  (syslog: `Failed to open package file`, then the script fails with 127).
  The same affects every package's pre-uninstall script on this tree.
- Starting app_server through a shell wrapper (`exec`): app_server came up
  with 4 threads and no client could connect ("You need to have a valid
  app_server connection first!").

## Verified

On the RENKU arm64 VM at 2560x1600 (QEMU `virtio-gpu-pci,xres=2560,yres=1600`),
with the patched `app_server` and `libtracker.so` built from the arm64 tree:

- app_server reads QEMU's EDID (65x41 cm, 100 dpi) and chooses 1x, which is
  right for that size. QEMU cannot present a small high-density panel, so the
  2x path was checked by setting 24 pt fonts by hand.
- At 24 pt, icons saved at 1x (home, Trash, the boot volume) move to their
  2x grid cells instead of overlapping, the attribute records 2.0, and a
  restart does not scale them a second time.

x86_64: RenkuOS `nightly` built with both patches (`@nightly-anyboot`) and
booted in QEMU (`virtio-vga,xres=2560,yres=1600`, TCG) on the Mac mini: the
same 1x decision from QEMU's EDID; at 24 pt five desktop items saved at 1x
moved to exactly twice their coordinates, `_trk/pinfo_scale` became 2.0, and
further restarts left the attributes byte-identical.

Package: on the arm64 VM, `pkgman install rretina` from pkgman.rainygirl.com
put the patched files in place (md5 of `/boot/system/servers/app_server` and
`/boot/system/lib/libtracker.so` changed at once), the system rebooted with
`shutdown -r` into the patched app_server, Tracker and Deskbar; `pkgman
uninstall rretina` restored the stock md5s at once and the next boot ran the
stock app_server.

UI scale (0003, rretina 1.0.0-2): on the arm64 test VM, choosing Automatic
wrote `auto` and set 12 pt (QEMU's 100 dpi); with 24 pt then saved and a
reboot, app_server logged "UI scale 1.00" and the desktop came back at 1x
with its icons moved to the 1x grid. In a QEMU window on the Mac
(`-display cocoa`, `virtio-gpu-pci,xres=2560,yres=1600`) QEMU reports a
51x32 cm display; with no sizes chosen app_server picked 1.25.

## Known, not fixed here

- A volume whose file system cannot hold attributes (network shares such as
  R SMB) gets auto-placed on every start and can land on another icon. This
  happens at 1x too.
- Applications running when the font size changes keep the old size until
  they are restarted (unchanged Haiku behaviour).
- The scale is decided at boot; plugging in a display of another density
  does not change it until the next boot.

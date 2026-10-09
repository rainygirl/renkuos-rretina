# renku-retina

HiDPI ("Retina") patches for RenkuOS, x86_64 and arm64. They apply to
RenkuOS/Source (`main` and `nightly` as of 2026-10-09) with `git apply`.

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

## Verified

On the RENKU arm64 VM at 2560x1600 (QEMU `virtio-gpu-pci,xres=2560,yres=1600`),
with the patched `app_server` and `libtracker.so` built from the arm64 tree:

- app_server reads QEMU's EDID (65x41 cm, 100 dpi) and chooses 1x, which is
  right for that size. QEMU cannot present a small high-density panel, so the
  2x path was checked by setting 24 pt fonts by hand.
- At 24 pt, icons saved at 1x (home, Trash, the boot volume) move to their
  2x grid cells instead of overlapping, the attribute records 2.0, and a
  restart does not scale them a second time.

x86_64 has not been built or run yet; the changes are architecture-neutral.

## Known, not fixed here

- A volume whose file system cannot hold attributes (network shares such as
  R SMB) gets auto-placed on every start and can land on another icon. This
  happens at 1x too.
- Applications running when the font size changes keep the old size until
  they are restarted (unchanged Haiku behaviour).
- The scale is decided at boot; plugging in a display of another density
  does not change it until the next boot.

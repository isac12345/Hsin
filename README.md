# HSIN

HSIN is a performance module for rooted Android devices, shipped with a
companion app. The module runs as a Magisk or KernelSU module and adjusts
performance continuously, per application, while the app provides the
interface, the on-screen overlay and the reports.

The goal is stability rather than maximum benchmark numbers: the module raises
performance only while an application actually needs it and lowers it again
when the device is comfortable.

## Tested hardware

The current release was developed and tested on one device only:

| Item | Value |
|---|---|
| Device | itel P65 |
| SoC | Unisoc T606 |
| Android | 14 |
| Root | KernelSU |

Other devices are untested. At boot the module detects the chipset, the number
of CPU cores and the amount of RAM, and selects one of three internal classes
(`low`, `mid`, `high`). Chipsets with a known profiles file in
`module/uperf/config` get CPU placement through uperf; unknown chipsets fall
back to a generic path. Features that a device does not support are skipped and
recorded in the log instead of being forced.

## Requirements

- Android 8.0 or newer (the app requires API 26; the module itself is plain
  shell and works on older releases, but is untested there).
- Root through Magisk or KernelSU. APatch is not tested.
- About 30 MB of free space in `/data`.

## Features

- **Adapt mode** - per-application GPU load levels 0 to 3, chosen from measured
  frame timing and pressure, with temperature and battery limits.
- **Peak mode** - fixed performance profile, Overdrive enabled, Adapt disabled.
- **Floating panel and adaptation wheel** - on-screen orb showing load, FPS and
  temperature, with mode switching and screen recording.
- **Adapt report** - per-application history: load, session count, 1% low,
  average FPS, jank percentage, longest stall.
- **Automatic FPS cap** - for a game without a cap, the module measures the
  device and selects the highest refresh rate it can hold, once per session.
- **Per-game hooks** - process priority, I/O priority, out-of-memory score,
  Do Not Disturb, renderer and resolution options.
- **Memory cleaner** - optional, acts only while a game runs and only under
  memory pressure.
- **Game space interface** - game list, recordings, settings, switchable
  language (Indonesian and English).

## Installation

1. Download `HSIN-v5.0-module.zip` from the latest release.
2. Install it as a module:
   - Magisk app: Modules, Install from storage.
   - KernelSU app: Modules, Install from storage.
3. Reboot.
4. Open the HSIN app. It is bundled inside the module zip and installed during
   installation.

A standalone `HSIN-v5.0.apk` is also published for devices where the in-module
installation is not possible. The app requires root to talk to the module.

If an older module with the same identifier is installed, this release replaces
it. Remove the old app first so that only one HSIN app is present.

## Basic usage

- Open the app and choose a mode on the first screen. `Adapt` is the
  recommended mode for daily use. `Peak` disables adaptation entirely.
- Open a game or any application; the module adapts while it is in the
  foreground.
- The floating orb shows the current load. Double tap records FPS, long press
  switches mode; both can be changed in settings.
- The Adapt report tab lists every application the module has measured.
- The command line interface is available for debugging:
  `su -c "sh /data/adb/modules/hsin/common/hsinctl.sh status"`.

## Uninstall

- Magisk: Modules, remove HSIN, reboot.
- KernelSU: Modules, remove HSIN, reboot.
- Or delete `/data/adb/modules/hsin` and reboot.

Removing the module reverts the changes it made; see `docs/SAFETY.md` for the
exact list. Application data in `/data/adb/hsin` is kept so that reinstalling
restores the learned per-application state. Delete that directory manually if
you want a clean start.

## Documentation

- `RELEASE.md` - release notes for the current version.
- `docs/HOW-IT-WORKS.md` - how the module and the app work, with the actual
  thresholds taken from the source.
- `docs/SAFETY.md` - what the module changes, how to recover from a boot loop,
  known risks.
- `THIRD-PARTY.md` - components used, their authors and licenses.
- `CONTRIBUTING.md` - how to build and test.
- `SECURITY.md` - how to report a security issue.

## License

GNU General Public License v3.0. See `LICENSE`. Third-party components keep
their own licenses; see `THIRD-PARTY.md`.

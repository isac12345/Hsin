# Release notes

## HSIN v5.0

Version code 99. Module and companion app share the same version.

### Summary

Fifth public line of the module, with the Adapt engine rewritten around
measured results instead of fixed timers. The release adds an automatic FPS cap
selection, a per-application report, and an on-screen adaptation wheel. The
module and the app communicate only through `hsinctl.sh`.

### Highlights

- **Adapt mode.** Per-application GPU load from 0 to 3, raised only while the
  application janks and lowered again when it is comfortable. A raise is judged
  after the fact: if it does not improve jank it is abandoned and the previous
  level returns. See `docs/HOW-IT-WORKS.md`.
- **Long session stability.** The first 90 seconds of a game session do not
  consume the raise allowance, the allowance is refilled every 10 minutes of
  play, and the monitored SoC temperature (70 C hold, 75 C force) complements
  the battery limits (48 C hold, 50 C force).
- **Peak mode.** Performance profile with Overdrive, adaptation disabled.
  The adaptation wheel stays still, as documented.
- **Adaptation wheel and floating panel.** Orb showing load, FPS, GPU and
  temperature; double tap records FPS, long press switches mode.
- **Adapt report.** Per-application history: session count, load on battery and
  on charger, 1% low, average FPS, jank percentage, longest stall.
- **Automatic FPS cap.** For a game without a cap, the module selects the
  highest refresh rate whose 1% low stays at 92% of that rate, once per
  session, respecting the display maximum. A cap set by the user is never
  overwritten.
- **Notification.** Persistent notification while the service runs, with the
  current mode.
- **Per-game hooks.** Process and I/O priority, out-of-memory score, Do Not
  Disturb, renderer, resolution downscale, refresh rate, game mode API.
- **Memory tools.** Optional memory cleaner under pressure, optional MGLRU
  switch, manual clear button in the app.
- **Interface languages.** Indonesian and English.

### Installation

Flash `HSIN-v5.0-module.zip` in Magisk or KernelSU and reboot. The app is
installed from inside the zip. A standalone APK is published for manual
installation. See `README.md`.

### Known limitations

- The release has been tested on a single device: itel P65, Unisoc T606,
  Android 14, KernelSU. Other devices and other root managers are untested.
- FPS and 1% low come from SurfaceFlinger layer information. On some games and
  some ROMs that information is missing or wrong; without it the engine falls
  back to pressure and memory signals, which react more slowly.
- The automatic FPS cap cannot raise a cap that already exists. Games seeded
  with a fixed cap keep it until the cap is removed by the user.
- There is no auto-update. New builds are installed manually.
- The APK is signed with the project signing key. Builds made without the
  signing secrets are signed with a debug key and cannot replace an installed
  release build.
- Only ARM64 and ARMv7 are supported; x86 devices are not.

### Upgrade notes

- Upgrading from an older module with the same identifier replaces it. Reboot
  after flashing.
- The state directory `/data/adb/hsin` is kept. Learned per-application data
  from previous versions is compatible; if the behaviour looks inconsistent,
  delete that directory and reboot.
- The companion app requires Android 8.0 or newer and root.
- Remove any older companion app before installing this one so that only one
  HSIN app is present.

### Checksums

Fill in after the CI build that produces the published artifacts.

```
<sha256>  HSIN-v5.0-module.zip
<sha256>  HSIN-v5.0.apk
```

The CI run also publishes `SHA256SUMS.txt` next to the artifacts in the draft
release.

### Verification

```
sha256sum -c SHA256SUMS.txt
unzip -l HSIN-v5.0-module.zip | head
```

Inside the module zip, `module.prop` must show `version=5.0` and
`versionCode=99`.

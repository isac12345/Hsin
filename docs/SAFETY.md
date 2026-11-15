# Safety

HSIN modifies a rooted Android device. This page lists what it changes, how to
recover when something goes wrong, and the known risks. Read it before
installing on a device other than the one listed in `README.md`.

Root modules can leave a device unable to boot. Keep a way to reach recovery or
fastboot before installing anything.

## 1. What the module changes

All writes happen from `monitor.sh` and the scripts it calls. The app never
writes kernel values itself.

### Graphics

- Adreno style kbase parameters (`/sys/class/kgsl/kgsl-3d0/...`) and Mali kbase
  parameters (`/sys/module/mali_kbase/parameters/...`): boost, poll interval,
  upthreshold. Level 0 restores the values the kernel had.
- GPU devfreq paths (`/sys/class/devfreq/...`) only where detection found them.
- Properties `vendor.perf.framepacing.enable`, `persist.sys.framepredict.enable`
  and `debug.sf.latch_unsignaled` (the last one only when the marker file
  `SF_LATCH_UNSIGNALED` exists in `/data/adb/hsin`).

### CPU

- CPU frequency limits (`/sys/devices/system/cpu/cpu*/cpufreq/...`) and
  scheduler util clamp, per profile.
- cpuset and scheduler placement for the foreground application. If uperf is
  present and the chipset is supported, placement is delegated to it.

### Thermal

- Thermal zone trip points and cooling device limits
  (`/sys/class/thermal/...`), used by profiles and guards. Values are read
  first and written only when a supported node is found.
- Battery and SoC temperature are read every iteration; temperature is never
  written except to thermal trip points as part of a profile.

### Power

- Charge limit, when enabled by the user (`/sys/class/power_supply/...`).
- Screen refresh rate while a game runs (`cmd display set-user-preferred-display-mode`).

### Memory and storage

- Optional memory cleaner: `am kill-all`, which kills cached background
  processes only (see `docs/HOW-IT-WORKS.md`, section 6).
- Optional MGLRU switch writes `/sys/kernel/mm/lru_gen/enabled`, and restores
  the previous value on `off`.
- `fstrim` on all partitions, only outside a game and only above 15% battery.
- Block device read-ahead and I/O scheduler values.

### Applications

- Per-game renderer, resolution downscale, FPS cap and game mode through
  `cmd game set` and `cmd game reset`.
- Freezing an application the user selected with `pm disable-user --user 0`.
  Uninstalling the module re-enables every application listed in
  `/data/adb/hsin/frozen.list`.

### Hosts based ad blocking (opt in)

The ad blocker bind-mounts a generated hosts file over `/system/etc/hosts`. The
partition is not modified; unmounting or rebooting restores the original file.
Do not run it together with another hosts module.

## 2. Boot guard

`service.sh` waits up to 120 seconds for `sys.boot_completed=1`. A failed boot
increments the counter in `/data/adb/hsin/.boot_fail_count`; a successful boot
resets it.

After two consecutive failed boots the module stops applying tuning and
records the event in `hsin.log`. It stays installed but inactive, so the device
can boot normally and the module can be inspected or removed. The state is kept
on purpose: the module does not silently re-enable itself.

## 3. Recovery from a boot loop

In order of preference:

1. **KernelSU or Magisk safe mode.** Hold the volume-down key while booting
   (KernelSU) or use the Magisk safe mode gesture. Both disable all modules
   without removing them. Then remove or disable HSIN in the manager.
2. **Remove the module from recovery.** In a custom recovery with `/data`
   mounted:

   ```
   adb shell rm -rf /data/adb/modules/hsin
   adb shell rm -f /data/adb/modules/hsin/disable
   ```

   Alternatively create the empty file `/data/adb/modules/hsin/disable`, which
   lets the manager skip the module on the next boot.
3. **Disable the tuning without removing the module.** Create
   `/data/adb/hsin/.disable_tweaks`, or set `DISABLE_TWEAKS=1`; both skip every
   tuning step and every daemon at the next boot.
4. **Clear the saved state.** Deleting `/data/adb/hsin` removes settings,
   learned per-application data and game lists. This is safe: the module
   recreates the directory with defaults.

After removing the module, reboot. All sysfs values return to their kernel
defaults on reboot; nothing HSIN wrote survives.

## 4. What uninstalling reverts

The uninstall script:

- turns the charge limit off;
- re-enables every application listed in `frozen.list`;
- stops the monitor, watchdog and auto profile daemons, matching them by
  command line rather than by pid;
- leaves `/data/adb/hsin` in place unless the manager removes it.

Unmounting the hosts override happens through the ad blocker's own `off`
command; the bind mount disappears on reboot in any case.

## 5. Known risks

- **Only one device has been tested.** Chipset detection covers many SoCs, but
  an untested kernel may expose a node with different semantics. The module
  writes only after a capability check, but a check can be wrong.
- **Thermal writes.** Trip point changes can make a device run warmer than its
  vendor intended. The temperature guards exist for this reason; do not raise
  them without a way to measure the SoC temperature.
- **Frame timing depends on the FPS source.** The FPS daemon reads
  layer information that some ROMs and games do not provide. Without it the
  engine falls back to pressure and memory signals, which react more slowly.
- **Freezing applications** makes them disappear from the launcher until they
  are enabled again. Do not freeze system-critical packages.
- **Hosts override** is incompatible with other hosts modules and with the
  Private DNS setting; the module logs a warning but cannot detect every case.
- **Updates.** Flashing a new module build over an old one keeps the state
  directory. If behaviour looks inconsistent after an update, delete
  `/data/adb/hsin` and reboot.
- **No auto-update.** The module never downloads or installs anything by
  itself.

## 6. No warranty

HSIN is provided as is, without warranty of any kind, as stated in the GNU
General Public License v3.0. Root modifications can void the device warranty,
trigger vendor security warnings, or, if used incorrectly, make the device
unbootable or unrecoverable without a full data wipe. You install it at your own
risk.

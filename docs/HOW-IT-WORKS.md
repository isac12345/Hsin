# How HSIN works

This document describes the parts of HSIN that matter when operating or
modifying it. Every number below is taken from the source in `module/common`;
when the source changes, this document has to change with it.

HSIN has two halves:

- the **module** (`module/`), plain POSIX shell, executed by the root manager
  at boot and kept running by a monitor loop;
- the **companion app** (Kotlin, Jetpack Compose, package `com.hsin`), which
  never touches the system directly: every action is a call to
  `hsinctl.sh` through a root shell.

Keeping all system logic in the module is deliberate. The app can be replaced,
rebuilt or uninstalled without leaving a second writer for the same kernel
values.

## 1. Boot sequence

`service.sh` runs after boot:

1. Waits for `sys.boot_completed=1`, at most 40 iterations of 3 seconds
   (120 s). Failing that, it counts the boot as failed; two consecutive failed
   boots activate the boot guard and skip all tuning (see `docs/SAFETY.md`).
2. Rotates `hsin.log` when it exceeds 2 MB.
3. Deletes leftover transient boost state from older versions.
4. Detects hardware (`detect.sh`): SoC vendor, chipset family, CPU policies,
   GPU, thermal zones, refresh rate, RAM, core count, and the device class
   `low`, `mid` or `high` (low: low-RAM build flag, at most 4 cores, or at
   most 3 GB RAM; high: at least 6 GB RAM and at least 8 cores; otherwise
   mid).
5. Applies the stored profile, then starts `monitor.sh` and the helper
   daemons (watchdog, auto profile).

## 2. Monitor loop

`monitor.sh` is the only writer for the values HSIN owns. It runs forever:

- screen on: one iteration every 7 seconds;
- screen off: every 60 seconds;
- foreground game polling: every 2 seconds.

In event mode (the normal case) the tick is 2 seconds while a game is in the
foreground and `EVENT_IDLE_SECS` = 6 seconds otherwise (`HSIN_EVENT_IDLE_SECS`,
max 30; a `MONITOR_LOOP_SECS` override wins). The screen state is read from the
backlight node (`/sys/class/backlight/*/brightness` > 0 means on) and `dumpsys
power` is only run when that is unavailable or reads 0 (`HSIN_SCREEN_FAST=0`
disables the shortcut). Sensors, timestamps and the HUD sampler use shell
builtins instead of `cat|tr|sed|date|cut` child processes: measured with
`strace -f` on the sandbox harness, the monitor tick went from about 23 to 6
`execve` calls and `hud_sample.sh --loop` from about 16 to 3 per tick.

Each iteration reads the foreground package, updates the game hooks, runs the
Adapt engine for that package, runs the memory cleaner when a game is active,
and writes the current state.

### 2.1 Safety nets in the monitor

- **Start-up sweep.** When the monitor starts (first boot or restarted by the watchdog) it
  releases whatever a dead predecessor left behind: game boost (`.gb_active`), game hooks
  (DND, refresh, I/O priority) and the Adapt frequency floors, including `uperf`/`fas-rs`
  processes that were stopped with `SIGSTOP`. The list of stopped pids is written (tmp + mv)
  before the signal is sent, and thawing also resumes the live `uperf`/`fas-rs` pids.
- **Pause switch.** `hsinctl pause on|off|get` (app: Tools, "Pause HSIN") creates `.paused`.
  The monitor then releases everything once, applies nothing, and only checks the flag every
  5 seconds. It stays paused across reboots until switched off.
- **FPS daemon revival.** While a game runs the monitor checks every ~20 s that the daemon pid
  is alive and restarts it through `hud_sample.sh --fpsd` (at most 5 times per game). A daemon
  that is alive but stuck cannot be detected from shell; that needs a heartbeat in `hsin-fpsd`.
- **`hsinctl status` cache.** The output is kept for 2 seconds in `.status.cache`; any other
  `hsinctl` command removes it so a change shows up in the next status. `fpsd_state` reports the
  FPS reader (`ok`, `dead`, `none`, `binder-fail`, `dump-fail`).

## 3. Adapt engine

The engine is `adapt.sh`. It keeps one load level per application, from 0 to
3, and writes the GPU parameters of that level through a single writer.

### 3.1 Load levels

Each level is a triple `boost poll upthreshold` written to the GPU kbase
parameters (Adreno style). Level 0 reproduces the values the kernel had before
HSIN touched them on the reference device:

| Level | boost | poll | upthreshold |
|---|---|---|---|
| 0 | 0 | 8 | 88 |
| 1 | 0 | 4 | 75 |
| 2 | 1 | 2 | 55 |
| 3 | 1 | 1 | 30 |

Level 0 means "change nothing". On other GPU families the module writes the
equivalent parameters that detection found; when no supported parameter is
found the level has no effect and the log records it.

### 3.2 Jank detection

One iteration is considered janky when any of these is true:

- 1% low below `AD_TARGET_P1` = 20 FPS (only when the average is at least
  `AD_AVG_MIN` = 15 FPS);
- 1% low below 65% of the average (`AD_P1_RATIO` = 65), which catches short
  drops that a good average hides;
- longest stall above 300 ms (`AD_STALL_JANK`);
- otherwise, when frame data is absent: CPU pressure `some avg10` at least 60,
  I/O pressure at least 20, or less than 400 MB of available RAM
  (`AD_MEM_MIN_KB` = 400000).

An iteration counts as calm only when none of the jank conditions is present
and CPU pressure is below 30, I/O pressure below 10, and available RAM at least
700 MB.

### 3.3 Raising and lowering

- Raise after `AD_RAISE_SECS` = 15 seconds of continuous jank, only if at least
  `AD_CHG_GAP` = 30 seconds have passed since the last change.
- Maximum `AD_MAX_RAISE` = 2 raises per session. The allowance is refilled
  every `AD_RAISE_RESET` = 600 seconds of session time.
- The first `AD_WARM_SECS` = 90 seconds of a game session do not count as jank
  and do not consume the allowance, so loading screens do not spend it.
- Lower after `AD_LOWER_SECS` = 60 seconds of continuous calm, or immediately
  when a critical temperature is reached.
- Between two changes there is always a gap of at least 30 seconds.

### 3.3a What the statistics count

- One statistics sample is taken per `AD_SAMP_GAP` = 10 seconds (the length of one
  FPS-daemon window), not per monitor tick. Samples are therefore real time:
  `n` = 24 is about 4 minutes of play, `n` = 60 about 10 minutes.
- `jank_pct` is "share of sampled play time that was janky" (1% low below target,
  strong frame-pacing drop, or a long stall). It is not a frame count. The session
  summary in the app counts individual slow frames instead, so the two numbers are
  different measures and are labelled differently in the app ("janky time" vs "jank").
- Gaps of `AD_STALL_LOADING` = 1500 ms or more are treated as loading and are not
  recorded. The warm-up (first 90 s) is not recorded either.
- Auto tune needs `n` >= 24; presets and suggestions need `n` >= 60.
- History is capped at `AD_HIST_MAX` = 2000 samples; above that, `n`, `sum_p1` and
  `jank_n` are scaled down together so averages and percentages are unchanged but a
  new session can still move them. `p1_min` and `stall_max` are kept for life.
- Samples are saved every 60 seconds (only when there is something new), so a crash
  or reboot loses at most one minute.
- Data written by earlier versions (one sample per 2 s tick) is migrated once by
  dividing `n`, `sum_p1` and `jank_n` by 5 (marker `.stats_v2`); averages and
  percentages stay the same.
- If a game produces no FPS sample 60 s after warm-up, one warning with the
  `fpsd.status` line is written to `hsin.log`.
- When a session opens, Adapt points the FPS daemon at that game
  (`hud_sample.sh --fpsd <pkg>`, which also starts the daemon if it died). Without
  this the daemon kept measuring whichever app the HUD last asked for, and every
  sample was rejected by the package check.

### 3.4 Did the raise help

Before raising, the engine records the jank rate of the current window. After
the raise it compares:

- helped: the jank rate improved at all compared with the window before the
  raise, or the current window is already at most 100 janky samples per 1000;
- not helped: the level is abandoned (`AD_BAD_LVL`) and the engine returns to
  the last level that helped (`AD_HELP_LVL`), at least level 1 for games.

The skip is cleared at every 10-minute refill, so a single bad measurement
cannot lock the level for the whole session.

### 3.5 Limits

| Rule | Value |
|---|---|
| Regular application maximum load | 1 |
| Game maximum load | 3 |
| Game starting load | 1 |
| Game minimum load | 1 (a game never drops to 0) |
| Maximum load while charging | 2 |
| Battery temperature, stop raising | 48 C |
| Battery temperature, force one level down | 50 C |
| SoC temperature, stop raising | 70 C |
| SoC temperature, force one level down | 75 C |
| Battery level, block raising | 15% or lower |
| Monitor interval | 7 s (screen on), 60 s (screen off) |

The battery sensor on the reference device rises slowly (41 to 44 C while the
SoC reaches 73 C), which is why the SoC limit exists as a second guard.

### 3.6 Peak mode

When the profile is `performance` combined with Overdrive (Peak), Adapt is
disabled: no application is measured, no load is changed, and the orb shows no
activity. Selecting any other profile resumes adaptation.

## 4. Automatic FPS cap

For a game that has no FPS cap yet, the engine selects one from measurement
instead of a fixed table:

1. after the 90-second warm-up, read the average FPS and the 1% low of the
   running game;
2. take the highest candidate refresh rate whose 1% low is at least 92% of
   that rate (`AD_FPS_HOLD` = 92), from the ladder 144, 120, 90, 60, 30, capped
   by the display maximum in `device_profile.env`;
3. write it through `hsinctl.sh gamefps set <package> <rate>`, which stores the
   FPS cap and the matching refresh rate;
4. record `fps_auto=<rate>` in the per-package state file and log the decision.

The selection happens once per game session. A cap that already exists, set by
the user or by the game seed list, is never overwritten. When no candidate
qualifies, nothing is written.

The new cap takes effect the next time the game is launched, because the
Android game mode API reads it when the game process starts.

## 5. Game hooks

For the foreground game the module applies, and removes on exit:

- process priority: `renice -10` on the game process, `renice -8` on its
  threads;
- I/O priority: `ionice -c 2 -n 0`;
- out-of-memory score: `oom_score_adj -300` for the game process only;
- Do Not Disturb, when enabled for that game;
- per-game renderer, resolution downscale, FPS cap and refresh rate, applied
  through the Android game mode API and surface flinger settings at launch;
- preload of the game process when enabled and when the device class is not
  `low`.

Each hook can be switched off per device and per application; a feature that
the device does not support is skipped and logged.

## 6. Memory cleaner

`memfx.sh` is opt-in (`MEMCLEAN=1`). It acts only while a game is in the
foreground, only when memory pressure `some avg10` stays above the threshold
taken from `ro.lmk.psi_partial_stall_ms` (70 ms by default, 200 ms on low-RAM
devices) for 3 consecutive samples, and at most once every 180 seconds. The
action is `am kill-all`, which kills cached background processes only.

When the ROM does not implement `am kill-all`, the module records that fact and
leaves cleaning to the app button instead of pretending to act.

A second option, `MEMCLEAN_ON_START=1`, frees memory once when a game starts.

## 7. State files

Everything lives in `/data/adb/hsin` (override: `HSIN_CONF_DIR`).

| Path | Content |
|---|---|
| `app.conf` | user settings and feature flags |
| `detected.conf` | hardware detection result |
| `device_profile.env` | derived caps: refresh maximum, thermal paths |
| `game_opts.conf` | per-game options: FPS, refresh, downscale, renderer, priority |
| `game_profile_map.conf` | per-game profile assignment |
| `adapt/<package>.conf` | per-application history and current load |
| `.adapt_now` | one line: package, load, is-game, timestamp; empty when idle |
| `hsin.log` | rotating log, one previous file kept |
| `monitor.pid` | pid of the running monitor |
| `fpsd.out` | FPS samples written by the FPS daemon while a game runs |

A per-application file holds:

```
sesi=49
n=120
sum_p1=1440
p1_min=12
stall_max=99
jank_n=15
p1_avg=12
jank_pct=12
beban=1
beban_cas=0
fps_auto=120
terakhir=2026-11-14 17:39
```

`beban` is the load used on battery, `beban_cas` the load used while charging.
`fps_auto` exists only when the module chose the cap itself.

## 8. hsinctl

`hsinctl.sh` is the only entry point the app uses. The most relevant commands:

| Command | Purpose |
|---|---|
| `status` | live key=value state: profile, temperature, battery, game |
| `profile <battery\|balanced\|performance>` | select profile |
| `flag get\|set\|clear <NAME>` | feature flags from a fixed list |
| `conf get\|set <KEY> [value]` | settings in `app.conf` |
| `thermal get\|set <60-90>` | warm temperature limit |
| `games`, `game add\|remove`, `game seed`, `game scan` | game list maintenance |
| `gamefps get\|set <pkg> <10-240\|off>` | FPS cap and refresh for one game |
| `gamefx get\|set <pkg> <option> <value>` | per-game options, including renderer |
| `refresh list\|get\|set <off\|Hz>` | refresh rate locked while a game runs |
| `adapt list\|get <pkg>\|reset` | adaptation history |
| `mem status`, `memclean status\|on\|off`, `mglru status\|on\|off` | memory tools |
| `shield ...` | hosts based ad blocker |
| `sessions [N]` | game session history |
| `diagnose` | one-shot summary of mode, temperature, FPS |
| `livecheck` | checks every feature and prints STATUS lines |
| `restore` | reverts every temporary change |
| `bugreport` | collects logs and state into the Download folder |

## 9. Companion app

The app is a thin client:

- it reads state through `hsinctl.sh` and displays it;
- it sends commands through `hsinctl.sh`;
- the floating overlay draws FPS, GPU load, temperature and the orb, reading
  the same state files;
- no timer in the app writes kernel values, reniced processes or FPS caps on
  its own.

The app requires root. Without root it starts but every action fails with the
error returned by `hsinctl.sh`.

### Profil CPU monitor (opsional)
`touch /data/adb/hsin/.profile` menyalakan, hapus berkas untuk mematikan. Tiap 30 tick monitor mencatat baris
`[PROFIL]` di log: tick CPU (1 tick = 10 ms, anak proses ikut) per fase `head` (layar/override/health),
`gb`, `fps`, `adapt`, `snap`. Proses pembaca event tidak termasuk. Tanpa berkas itu biayanya satu uji berkas per tick.

# Third-party components

HSIN includes or redistributes the components below. Each keeps its own
license. Files under `module/fasrs` and `module/uperf` are unmodified upstream
builds unless stated otherwise.

## Runtime components shipped in the module

### fas-rs

- Upstream: https://github.com/shadow3aaa/fas-rs
- Author: shadow3aaa and contributors
- License: GNU General Public License v3.0
- Files: `module/fasrs/fas-rs` (binary), `module/fasrs/games.toml`,
  `module/fasrs/*.sh`
- SHA-256 of the bundled binary:
  `8560dec97a5b7b90fcb3cab2cd1fa8b5e2079ff400b639d8bfa7fe5a5073dbe8`
- Version: the bundled build is an upstream release; the exact upstream commit
  is not recorded in this repository. The corresponding source is available at
  the upstream repository above, and a written offer to provide the source of
  the exact build applies to every release: open an issue in this repository
  and the source archive will be published with the next release.
- HSIN does not modify this binary. It is used as a frame aware scheduler,
  optional and disabled when the device reports no support.

### uperf

- Upstream: https://github.com/yc9559/uperf
- Author: Matt Yang
- License: Apache License 2.0
- Files: `module/uperf/bin/uperf` (binary), `module/uperf/config/*.json`,
  `module/uperf/script/*`
- SHA-256 of the bundled binary:
  `f1265757009ff0c85dd8587d9e7bfcf5e51d10d36fe5e1341688215ae1fb49d8`
- Used for CPU placement and thread classification when the chipset has a
  matching profiles file. The license text is reproduced in
  `module/uperf/LICENSE`.

### BusyBox

- Upstream: https://busybox.net
- License: GNU General Public License v2.0
- File: `module/uperf/bin/busybox/busybox`
- SHA-256: `ee76e1eed5e39ef12c1e23b9d56cad305ad566de78151db0351b3efdcc1e1c11`
- Version: the bundled build reports its applet set but not a release string;
  the corresponding source is available from the upstream project and from any
  distribution that ships the same build.
- Used only by scripts that need applets missing from the device toolbox.

### AsoulOpt

- Upstream: https://github.com/nakixii/Magisk_AsoulOpt
- Author: nakixii
- License: no license file is published upstream. The bundled zip is
  redistributed as part of the module installation flow only; it is installed
  by the user's root manager when the user runs the module installer.
- File: `module/uperf/modules/asoulopt.zip`
- SHA-256: `90dee40e952a183f56e82baf1565e01261cc7b85d2dfc92b57af044351382f6f`
- Because no license is declared upstream, treat this component as
  all-rights-reserved. If you redistribute HSIN, remove this file or obtain
  permission from its author first. HSIN degrades gracefully when the file is
  absent: installation is skipped and logged.

## Data

### gamebank.txt

- Source: `gamelist.txt` from Encore Tweaks,
  https://github.com/Rem01Gaming/encore_tweaks
- Author: Rem01Gaming
- License: Apache License 2.0
- File: `app/src/main/assets/gamebank.txt`
- Content: package names only. No game artwork, logos or other copyrighted
  assets are included. See `NOTICE-gamebank.md`.

## Build-time dependencies (not redistributed as source)

The companion app links the following, all under the Apache License 2.0 unless
noted:

- AndroidX libraries (Core, Activity, Lifecycle, Compose UI, Material 3)
- Kotlin standard library and Kotlin coroutines (Apache License 2.0)
- Jetpack Compose compiler and runtime
- Google Accompanist-free equivalents built in-tree

Full transitive versions are resolved by Gradle from `app/build.gradle.kts`.

## Code in this repository

- `module/common`, `module/*.sh`, `app/src/main/java/com/hsin`:
  Copyright the HSIN authors, GPL-3.0.
- `app/src/main/java/com/hsin/zrec`: screen recording integration. No
  third-party header was found; treated as project code. If you recognize this
  code as yours, open an issue so attribution can be added.
- `native/hsin-fpsd.c`: project code, GPL-3.0.
- `module/fasrs` and `module/uperf` script wrappers: project code that invokes
  the upstream binaries above.

## Reporting a licensing problem

If a component is missing attribution or is included without a valid license,
open an issue titled `licensing: <component>` or use the private channel in
`SECURITY.md` when the report itself is sensitive. Such reports are handled
before the next release.

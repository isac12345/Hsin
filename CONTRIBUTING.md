# Contributing

## Before you start

- Read `docs/HOW-IT-WORKS.md` for the architecture and the actual thresholds.
- All system logic belongs in the module (`module/common`, POSIX shell). The
  app (`app/`) is a client: it must call `hsinctl.sh` instead of writing kernel
  values, renicing processes or clearing memory on its own.
- Keep one writer per value. A second writer for the same kernel parameter is
  a bug, not an improvement.

## Build and test

Local:

```
sh tools/check_module.sh
sh tools/selftest/test_adapt.sh
shellcheck -S error module/common/*.sh
```

The Android unit tests run through Gradle:

```
./gradlew :app:testDebugUnitTest
```

If Gradle cannot run locally, push a branch and use the GitHub Actions build:
the workflow runs `tools/check_module.sh` and compiles the app.

## Rules for changes

- One change per commit, with a message that states what changed and why.
- Do not add placeholder code, stubs or features nobody asked for.
- Do not change the version (`version.txt`) in a pull request unless the change
  is a release.
- Every new behaviour in the Adapt engine needs a test in
  `tools/selftest/test_adapt.sh`. Tests set their own parameters; they must not
  depend on the defaults of the device.
- Keep the log honest: a skipped feature must be logged as skipped, never
  reported as applied.
- Update `docs/HOW-IT-WORKS.md` when a threshold, interval or state file
  changes. The document is the reference for users and reviewers.

## Pull requests

- Describe the problem, the change and how you verified it.
- Include the command output of the tests you ran.
- State what you did not test and why.
- Keep the diff minimal; unrelated formatting changes make review harder.

## Licensing

Contributions are accepted under the GNU General Public License v3.0, the same
license as the project. By opening a pull request you confirm you have the
right to submit the code under that license. Add third-party components to
`THIRD-PARTY.md` with author, license and source.

# Security policy

## Supported versions

Only the latest release receives fixes. Older builds are not patched.

## Reporting a vulnerability

Report privately. Do not open a public issue for a vulnerability.

Use GitHub's private vulnerability reporting for this repository:
Security tab, then "Report a vulnerability". If that is not available, contact
the maintainer through the GitHub account that owns the repository and ask for
a private channel before sending details.

Include:

- the affected version (`version.txt` value or release name);
- the device, Android version and root manager;
- what an attacker can do, and what access is required to do it;
- reproduction steps or a proof of concept;
- any suggested fix.

## What to expect

- Acknowledgement within 7 days.
- An assessment and a plan within 14 days.
- Credit in the release notes unless you ask to stay anonymous.

## Scope

In scope:

- the module scripts in `module/`;
- the companion app in `app/`;
- the native FPS daemon in `native/`;
- the CI workflow and release artifacts.

Out of scope:

- issues that require an already-compromised root environment;
- vulnerabilities in third-party components (report them upstream; see
  `THIRD-PARTY.md`);
- the fact that a root module can change system behaviour by design.

## Handling of secrets

Signing material is never stored in the repository. CI receives it only through
repository secrets and writes it to a temporary directory that is not uploaded
as an artifact. If you find a secret in the repository or its history, report it
privately; do not paste it into an issue.

# Security Policy

## Reporting a Vulnerability

Do not file public issues for suspected vulnerabilities. Report them privately to Rafael Dina at `rafael.dina@gmail.com` with the affected revision, platform, reproduction steps, and expected versus observed behavior.

## Security Boundaries

- ELIS executes Lua game code supplied by the selected local game or archive; do not treat untrusted game content as sandboxed.
- Demo download, archive loading, sprite/tileset parsing, and project import/export consume external input. Changes in these paths should validate bounds and preserve the existing smoke coverage.
- Keep credentials, tokens, and local profile data out of the repository and test fixtures.
- Dependency or toolchain upgrades should be verified with `bash scripts/verify.sh` before release.

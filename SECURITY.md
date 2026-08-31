# Security Policy

## Reporting a Vulnerability

Do not file public issues for suspected vulnerabilities. Report them privately to Rafael Dina at `rafael.dina@gmail.com` with the affected revision, platform, reproduction steps, and expected versus observed behavior.

## Security Boundaries

- ELIS executes Lua game code supplied by the selected local game or archive; do not treat untrusted game content as sandboxed.
- Demo download, archive loading, sprite/tileset parsing, and project
  import/export consume external input. Manifest-backed packages require
  normalized unique paths, valid metadata, exact extracted lengths, declared
  executable files, and complete-package flash bounds. Changes in these paths
  should preserve hostile-input smoke coverage.
- Automatic source conversion pins `lupi-codec`; an explicitly supplied
  `LUPI_CODEC_DIR` remains the operator's trust decision.
- Keep credentials, tokens, and local profile data out of the repository and test fixtures.
- Dependency or toolchain upgrades should be verified with `bash scripts/verify.sh` before release.

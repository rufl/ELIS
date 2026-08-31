# Security Policy

## Supported versions

ELIS has no stable release series yet. Security fixes target the current `main`
branch. Historical commits and locally modified cartridges are unsupported.

## Reporting a Vulnerability

Do not file public issues for suspected vulnerabilities. Report them privately
to Rafael Dina at `rafael.dina@gmail.com` with the affected revision, platform,
reproduction steps, and expected versus observed behavior. Do not include live
credentials or sensitive third-party data. You should receive an acknowledgement
within seven days; coordinated disclosure timing will be agreed after triage.

## Security Boundaries

- ELIS executes Lua game code supplied by the selected local game or archive; do not treat untrusted game content as sandboxed.
- Demo download, archive loading, sprite/tileset parsing, and project
  import/export consume external input. Manifest-backed packages require
  normalized unique paths, valid metadata, exact extracted lengths, declared
  executable files, and complete-package flash bounds. Changes in these paths
  should preserve hostile-input smoke coverage.
- Automatic source conversion pins `lupi-codec`; an explicitly supplied
  `LUPI_CODEC_DIR` remains the operator's trust decision. Built-in acquisition
  permits HTTPS and HTTPS redirects only, rejects failed libcurl options, and
  stops each source archive at 64 MiB before the stricter 16 MiB package gate.
  Installation copies regular files and directories only and fails if staging
  directory creation, output flushing, or output closure fails.
- Keep credentials, tokens, and local profile data out of the repository and test fixtures.
- Dependency or toolchain upgrades should be verified with `bash scripts/verify.sh` before release.

# Releasing ELIS

This is the maintainer checklist for source publication and future tagged releases. It does not grant hardware approval to a cartridge.

## Source-publication preflight

1. Confirm the working tree contains no caches, captures, local projects, downloaded demos, credentials, or generated archives.
2. Review `LICENSE`, `REUSE.toml`, `THIRD_PARTY_NOTICES.md`, and every bundled cartridge's local license files; run `reuse lint`.
3. Check that `README.md`, `CHANGELOG.md`, `COMPATIBILITY.md`, `ROADMAP.md`, and `BACKLOG.md` agree on proof boundaries and unfinished work.
4. Recheck pinned upstream revisions when compatibility or conversion code changed.
5. Run the maintained gate:

   ```sh
   bash scripts/verify.sh
   ```

6. Run secret and workflow checks when available:

   ```sh
   gitleaks detect --source .
   actionlint .github/workflows/verify.yml
   git diff --check
   ```

7. Inspect the final commit and push only the intended branch and remote.

## GitHub settings after the first push

- Set the description to “Native Lupi simulator and deterministic Workshop editor in Zig.”
- Add topics such as `zig`, `lua`, `sdl2`, `fantasy-console`, `game-development`, and `level-editor`.
- Keep `main` as the default branch and require the `Verify / verify` status check before merge.
- Require pull-request review and block force-pushes or deletion on `main`.
- Enable Issues so the bundled forms are available.
- Enable GitHub private vulnerability reporting if available; keep the email path in `SECURITY.md` as a fallback.
- Do not publish a GitHub Release or mark Mr. Rescue hardware-approved until the documented release and named-board gates pass.

## Tagged source release

ELIS has no stable release series yet. Before the first tag:

- choose and document a semantic version;
- move user-visible entries from `CHANGELOG.md`'s Unreleased section into that version;
- state the supported host platform and dynamic-library requirements;
- publish checksums for every attached binary or archive;
- include `LICENSE` and `THIRD_PARTY_NOTICES.md` in distributions;
- verify binaries on a clean system matching the documented environment.

The current native build is dynamically linked and host-specific. Do not publish `zig-out/` from an arbitrary developer machine as a portable release.

## Cartridge certification

Simulator tests prove bounded software behavior, not a physical Lupi release. Hardware approval requires a named board and firmware revision plus retained worst-case frame-time, Lua-memory, and sustained-soak evidence. Third-party cartridge licenses and attribution travel with every distributed cartridge.

Mr. Rescue remains an explicitly unapproved physical-validation candidate until those measurements exist. Hex-a-Hop remains blocked until that approval.

## Rollback

Git tags and GitHub releases should be immutable. If a published artifact is wrong, mark the release affected, publish a corrected version, and retain the old checksums and explanation. Never silently replace a downloadable binary under the same version.

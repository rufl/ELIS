# Releasing ELIS

This is the maintainer checklist for source publication and future tagged releases. It does not grant hardware approval to a cartridge.

## Resumo em português (Brasil)

Este checklist orienta publicação do código-fonte e futuros releases; ele não
aprova hardware nem transforma um cartucho em release físico certificado.

Hoje não há uma série estável. Pacotes experimentais são host-specific,
unsigned e precisam passar pelos gates de build, smoke extraído, licenças,
checksums e revisão descritos abaixo. Linux é o host mantido; Windows tem
empacotamento experimental. Mr. Rescue não deve ser incluído como cartucho
aprovado, e medições em placa nomeada continuam obrigatórias para qualquer
alegação de validação física.

Os nomes de workflow, comandos e critérios normativos permanecem em inglês
para corresponder à configuração do repositório.

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
- Require pull requests and block force-pushes or deletion on `main`. The
  solo-maintainer policy requires documented code review and passing CI, but
  does not require another account's approval. Restore required peer approval
  when an independent maintainer is available.
- Enable Issues so the bundled forms are available.
- Enable GitHub private vulnerability reporting if available; keep the email path in `SECURITY.md` as a fallback.
- Publish ELIS binaries only after the binary release gates below pass. Mr. Rescue additionally requires named-board approval and is excluded from ELIS binary archives.

## Tagged source release

ELIS has no stable release series yet. Before the first tag:

- choose and document a semantic version;
- move user-visible entries from `CHANGELOG.md`'s Unreleased section into that version;
- state the supported host platform and dynamic-library requirements;
- publish checksums for every attached binary or archive;
- include `LICENSE` and `THIRD_PARTY_NOTICES.md` in distributions;
- verify binaries on a clean system matching the documented environment.

The current native build is dynamically linked and host-specific. Do not publish `zig-out/` from an arbitrary developer machine as a portable release.

## Binary prereleases

The initial candidate version is `0.1.0-rc.1`, not a stable release.
`.github/workflows/binaries.yml` builds Linux x86-64 on Ubuntu 24.04 and Windows
x86-64 using MSYS2 UCRT64. Linux archives require the documented system
libraries; Windows archives include their recursively resolved DLL dependencies
and license notices. Neither package includes Mr. Rescue.

Pull requests build packages and exercise extracted runtime and Workshop binaries
on fresh runners. The Windows smoke process removes MSYS2 and other development
directories from `PATH`. Both use SDL dummy video/audio rather than
an interactive desktop. Artifacts expire after 14 days and are not releases.

After documented code review and merge to protected `main`, dispatch **Binaries**
with the chosen prerelease version and `publish=true`. Publication requires both
platform builds and extracted-package smoke jobs to pass. It creates a prerelease
at the exact workflow commit with archives, dependency manifests, and SHA256SUMS.
Existing releases must not be overwritten. Binaries are unsigned; checksums
detect corruption but are not a substitute for code-signing identity.

## Cartridge certification

Simulator tests prove bounded software behavior, not a physical Lupi release. Hardware approval requires a named board and firmware revision plus retained worst-case frame-time, Lua-memory, and sustained-soak evidence. Third-party cartridge licenses and attribution travel with every distributed cartridge.

Mr. Rescue remains an explicitly unapproved physical-validation candidate until those measurements exist. Hex-a-Hop remains blocked until that approval.

## Rollback

Git tags and GitHub releases should be immutable. If a published artifact is wrong, mark the release affected, publish a corrected version, and retain the old checksums and explanation. Never silently replace a downloadable binary under the same version.

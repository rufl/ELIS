# Contributing to ELIS

ELIS welcomes focused bug fixes, compatibility fixtures, documentation improvements, Workshop refinements, and licensed cartridge work.

## Before opening an issue

- Search existing issues and [BACKLOG.md](BACKLOG.md).
- Use a minimal cartridge or `.elisworld` project that reproduces the behavior.
- Report security problems privately according to [SECURITY.md](SECURITY.md).
- Do not report a firmware-parity assumption as fact without an executable reference or named-device evidence.

## Development setup

The maintained environment is Linux with Zig 0.16.0. On Ubuntu 24.04:

```sh
sudo apt-get update
sudo apt-get install --yes --no-install-recommends \
  binutils gcc pkg-config python3 zip \
  libsdl2-dev liblua5.4-dev libzip-dev \
  libcurl4-openssl-dev libsndfile1-dev
```

Build both executables:

```sh
zig build native -Doptimize=ReleaseSafe
```

Read [ARCHITECTURE.md](ARCHITECTURE.md), [COMPATIBILITY.md](COMPATIBILITY.md), and the subsystem guide you intend to change. Workshop contributors should also read [STUDIO.md](STUDIO.md).

## Change discipline

- Keep each pull request focused on one behavior or one coherent documentation slice.
- Prefer a regression fixture before changing compatibility-sensitive code.
- Preserve explicit resource ceilings and fail closed on malformed external input.
- Pass allocators explicitly and pair every allocation, C handle, temporary tree, and SDL resource with cleanup on success and failure paths.
- Give each subsystem a module-level ownership comment. Keep named section boundaries in cohesive files and explain surprising invariants, cleanup duties, compatibility decisions, and proof limits; do not comment syntax the code already states.
- Run `zig fmt` on Zig files and keep Zig source lines within 100 columns.
- Do not add dependencies when an existing Zig, SDL, Lua, or repository facility is sufficient.
- Do not commit `.zig-cache/`, `zig-out/`, downloaded demos, local projects, captures, or credentials.
- Keep `REUSE.toml` annotations accurate when adding files under a non-MIT license; `reuse lint` must remain clean.

### Compatibility changes

Unlisted game-visible differences from the pinned Lupinho baseline are bugs. Intentional differences require:

1. a bounded executable fixture;
2. an entry in `COMPATIBILITY.md`;
3. no regression in valid upstream pixels or call ordering.

Provisional APIs remain blocked until executable firmware semantics exist. Do not infer behavior from documentation alone.

### Workshop changes

Authoritative mutation belongs in `src/studio/model.zig`; `src/studio_app.zig` owns presentation and transient interaction state. One user gesture must create at most one history entry. Mouse, keyboard, and controller paths must retain equivalent task coverage, safe focus behavior, and explicit save/discard ownership.

### Third-party cartridges

Do not relicense imported code, data, graphics, music, or text as MIT. Preserve source revision, license files, attribution, reproducible conversion, exact manifests, and package audits. Incomplete ports remain under `ports/`; promotion follows [demos/README.md](demos/README.md).

## Tests

Run the smallest relevant gate while developing:

```sh
bash scripts/test_studio.sh       # Workshop model/assets/input/debug
bash scripts/parity_smoke.sh      # renderer and API compatibility
bash scripts/runtime_smoke.sh     # runtime/package hostile input
bash scripts/studio_smoke.sh      # editor save/export/reload
bash scripts/mr_rescue_smoke.sh   # Mr. Rescue cartridge
```

Before requesting review, run:

```sh
bash scripts/verify.sh
reuse lint
```

Graphical tests must use an isolated disposable display. Never target a developer's active X11 or Wayland session. Physical FPS, memory, controller, or hardware approval claims require measurements from a named board.

## Pull requests

A reviewable PR includes:

- the problem and user impact;
- the chosen ownership boundary;
- focused test commands and results;
- compatibility, persistence, resource, UI, and licensing impact;
- updated user or contributor documentation when behavior changes.

Unless a pull request explicitly targets a separately licensed directory, you
agree that your contribution is provided under the repository's MIT License.
Contributions derived from third-party material must use that directory's
existing compatible license and preserve its attribution; they are never
silently relicensed as MIT.

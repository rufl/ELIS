# ELIS Definition of Done

This is the completion contract for ELIS backlog, roadmap, code, content,
release, and hardware work. It prevents an item from remaining “almost done”
indefinitely.

A work item is **done** only when every applicable gate below is satisfied and
its proof is recorded in the issue, pull request, backlog row, or release
record. A missing gate keeps the item open. A blocked gate is recorded as
`blocked`, with one concrete unblock condition; it is never silently treated as
complete.

## Universal gates

Every item must have:

1. **Bounded scope** — one observable outcome, named files or surfaces, and an
   explicit non-goal. New polish or follow-up work is a new item.
2. **Acceptance criteria** — finite checks that another maintainer can repeat;
   subjective “ready” or “looks good” is not a criterion by itself.
3. **Implementation** — source, content, configuration, or documentation is
   complete; no stubs, placeholders, fake fallbacks, or deferred TODOs remain
   in the item’s scope.
4. **Focused proof** — the smallest relevant maintained command, fixture, or
   inspection passes. A test that only checks wiring or source text is not
   proof of behavior.
5. **Regression boundary** — existing compatibility, persistence, resource,
   licensing, and security contracts remain green, or the intentional change
   is documented with a fixture and compatibility update.
6. **Documentation and evidence** — user/contributor docs, hashes, captures,
   measurements, licenses, or deployment records are updated when applicable.
7. **Reviewable closeout** — the change is committed, the working tree is
   clean, and no known in-scope failure remains. Follow-up ideas are split
   into separate backlog rows before closing the item.

`N/A` is allowed only with a written reason. “Not tested” is not `N/A`.

## Completion gates by work type

### Runtime, API, or compatibility change

- A deterministic regression fixture or focused smoke reproduces the intended
  behavior and fails for the plausible pre-fix failure.
- Allocations, C handles, SDL resources, temporary files, and external-input
  paths are bounded and cleaned up on success and failure.
- Compatibility-sensitive changes include an executable fixture and an entry
  in `COMPATIBILITY.md`.
- Provisional APIs remain open until an executable firmware/reference semantics
  source exists; documentation alone cannot close them.

### Cria or other UI/UX change

- The named user task works through every supported input path in scope
  (keyboard, pointer, and controller where supported), including focus loss and
  save/discard behavior.
- Save, export, reload, and the relevant playtest path pass; one gesture does
  not create duplicate history entries.
- The 960x600 compact and 1280x760 roomy layouts are checked, focus is visible,
  text remains legible, and `--reduce-motion` preserves information.
- An isolated capture or equivalent visual inspection is recorded. New labels,
  shortcuts, and limits are documented.

### Cartridge, port, or authored content

- The finite content inventory is complete and counted (levels, mechanics,
  assets, states, or screens); missing content is an open row, not a note.
- Deterministic simulator, renderer, package, and failure-path gates pass for
  the declared scope.
- Source revisions, conversion steps, licenses, attribution, manifests, and
  package-size/heap limits are exact and auditable.
- A desktop pass is labeled desktop-only until the separate hardware gate
  below passes.

### Release or deployment

- Linux and Windows artifacts are produced by CI, have immutable manifests and
  SHA-256 records, and pass extracted-package smoke on each target.
- Every target in scope passes ZTASH preview before mutation. Deployment is
  done only when the endpoint reports the requested version, build ID, SHA,
  size, and `active=true`.
- Partial fleet success stays open. A failed endpoint is recorded with the
  receiver error and a concrete unblock condition; it is not “published to the
  fleet.”
- Signing, public-release, hardware, or clean-machine claims are not implied
  by dogfood deployment.

### Named-device hardware proof

Hardware approval requires one named board and firmware revision, the exact
cartridge/package hash, and raw measurements attached to the proof record:

- sustained 60 Hz operation with worst-case frame time `<= 16.667 ms`;
- peak game Lua memory `<= 4 MiB`, with no allocation failure or unbounded
  growth;
- cartridge/package and asset limits remain within the applicable 16 MiB,
  49,152-pixel, and manifest ceilings;
- a continuous **30-minute** worst-case soak with no crash, reset, input lockup,
  renderer corruption, or monotonic memory growth.

The board, firmware, build configuration, test route, measurement tool, and
start/end timestamps must be named. Simulator evidence cannot satisfy this
section.

## Backlog lifecycle

- **Open**: acceptance criteria or proof are incomplete.
- **Blocked**: the remaining gate is external or unavailable; record the exact
  unblock condition and do not count the item as done.
- **Done**: every item-specific checklist and universal gate passes, with proof
  links/commands recorded in the row or its evidence file.
- **Archived**: only a done or explicitly retired row moves to
  `BACKLOG_ARCHIVE.md`; archival never substitutes for proof.

Every new backlog row must state its finite outcome, proof command or evidence
artifact, and hardware/release dependency if any. If a row grows new scope,
close the proven slice and create a new row instead of extending the original
indefinitely.

## Active ELIS item gates

The current three active rows use these final checklists.

### Mr. Rescue: Lupi Edition

Done requires all of the following:

- the 80 pinned upstream/port mechanics invariants and the complete scope in
  `demos/mr-rescue/PARITY.md` pass;
- `bash scripts/mr_rescue_smoke.sh`, the deterministic render matrix, and
  `python3 scripts/test_package_mr_rescue_playtest.py` pass;
- the complete licensed source/content inventory, exact manifests, attribution,
  package, Lua heap, and bounded-loop audits pass;
- the named-device hardware gate above is recorded for the exact cartridge hash.

### Hex-a-Hop: 100 levels

Done requires all of the following:

- Mr. Rescue is already hardware-approved;
- an exact manifest contains all 100 levels, with source revision, GPL/CC
  attribution, and no missing or duplicate level IDs;
- `bash scripts/hex_a_hop_smoke.sh` loads and completes every level through a
  deterministic route, and `python3 scripts/test_package_hex_a_hop.py` passes
  the failure-path and package gates;
- the resulting package passes the same heap, asset, manifest, named-board
  frame-time, memory, and 30-minute soak gates.

### Provisional console APIs

Done requires all of the following:

- a pinned executable firmware/reference implementation defines `ui.grid`,
  `ui.mouse`, pressure-valued input, and Clay layout semantics, including
  bounds, ordering, errors, and resource limits;
- each API has a simulator fixture and
  `bash scripts/provisional_api_parity_smoke.sh` compares it with the
  executable reference for normal, boundary, and invalid inputs;
- `COMPATIBILITY.md`, API documentation, and that focused parity command record
  the reference revision and observed behavior;
- no claim depends on prose-only or inferred firmware behavior.

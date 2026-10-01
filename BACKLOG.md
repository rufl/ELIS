# ELIS Backlog

## Source Of Truth Policy

`BACKLOG.md` is the canonical queue for accepted, incomplete ELIS work. `ROADMAP.md` describes direction, `CHANGELOG.md` records user-visible history, and `BACKLOG_ARCHIVE.md` retains completed or retired rows. The repository-wide [Definition of Done](DEFINITION_OF_DONE.md) defines the finite acceptance and proof gates; source code and a passing maintained verification command are required before a completed behavior is treated as proven.

- `[truth:policy]` Only maintainers promote work into this queue.
- `[truth:proof-gated]` A completed row needs a recorded passing proof command before archival.
- `[truth:source]` When documentation conflicts with implementation, the implementation and its passing proof boundary are authoritative until the documentation is corrected.

## Active Work

- [ ] [status:yellow] [truth:source] Complete Mr. Rescue: Lupi Edition as a separately licensed, full-fidelity port with original Classic mechanics and an optional child-friendly presentation mode. `demos/mr-rescue/` is explicitly authorized only as a named-board physical-validation candidate; hardware approval still requires its frame-time, memory, and soak proof. **Done only under [DoD: Mr. Rescue](DEFINITION_OF_DONE.md#mr-rescue-lupi-edition).**
- [ ] [status:yellow] [truth:source] Port all 100 Hex-a-Hop levels only after Mr. Rescue receives named-device approval. Preserve its undo/no-timer accessibility, isolate GPL/CC attribution, and apply the same fail-closed package and physical-device gates. **Done only under [DoD: Hex-a-Hop](DEFINITION_OF_DONE.md#hex-a-hop-100-levels).**
- [ ] [status:yellow] [truth:source] Close the newer provisional console-API gaps (`ui.grid`, `ui.mouse`, pressure-valued input, and Clay layout) only against executable firmware semantics; the public pinned simulator does not implement enough of that provisional documentation to support a truthful parity claim yet. **Done only under [DoD: provisional APIs](DEFINITION_OF_DONE.md#provisional-console-apis).**

## Completion rule

The three rows above are the complete current ELIS queue. A row remains open
until its linked item checklist and every applicable universal gate in
[DEFINITION_OF_DONE.md](DEFINITION_OF_DONE.md) pass. The generated OVERZEER
summary below mirrors these rows and is not an independent completion signal.

### Current evidence

- **2026-09-27 — Mr. Rescue software slice:** `bash
  scripts/mr_rescue_smoke.sh`, `python3 scripts/test_package_mr_rescue_playtest.py`,
  and `python3 scripts/test_mr_rescue_hardware_gate.py` passed. This proves the
  bounded desktop/package and proof-record paths; it does **not** close the
  named-board frame-time, memory, or soak gate.
- **2026-10-01 — rc.10 release and deployment:** main CI runs
  `36861519499` and `36861519466` passed Verify, Linux/Windows builds, and
  extracted-package smoke. Release run `36864402637` published
  `v0.1.0-rc.10` with per-target manifests, the aggregate ZTASH manifest, and
  passing SHA-256 records. DDJARIN and CHOPPER both report the exact rc.10
  package identity active and current; immutable values and deployment IDs are
  recorded in `.overzeer/elis-package-smoke-proof.md`.


<!-- OVERZEER:DOCS_BACKLOG_BEGIN -->
## OVERZEER project summary
- Git evidence in selected window: `35` commit(s).
- Documentation evidence: authored open tasks below; generated text is a proposal and does not mark work complete.
- [ ] [status:yellow] [truth:source] Complete Mr. Rescue: Lupi Edition as a separately licensed, full-fidelity port with original Classic mechanics and an optional child-friendly presentation mode. `demos/mr-rescue/` is explicitly authorized only as a named-board physical-validation candidate; hardware approval still requires its frame-time, memory, and soak proof.
- [ ] [status:yellow] [truth:source] Port all 100 Hex-a-Hop levels only after Mr. Rescue receives named-device approval. Preserve its undo/no-timer accessibility, isolate GPL/CC attribution, and apply the same fail-closed package and physical-device gates.
- [ ] [status:yellow] [truth:source] Close the newer provisional console-API gaps (`ui.grid`, `ui.mouse`, pressure-valued input, and Clay layout) only against executable firmware semantics; the public pinned simulator does not implement enough of that provisional documentation to support a truthful parity claim yet.
<!-- OVERZEER:DOCS_BACKLOG_END -->

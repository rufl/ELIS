# ELIS Backlog

## Source Of Truth Policy

`BACKLOG.md` is the canonical queue for accepted, incomplete ELIS work. `ROADMAP.md` describes direction, `CHANGELOG.md` records user-visible history, and `BACKLOG_ARCHIVE.md` retains completed or retired rows. Source code and a passing maintained verification command are required before a completed behavior is treated as proven.

- `[truth:policy]` Only maintainers promote work into this queue.
- `[truth:proof-gated]` A completed row needs a recorded passing proof command before archival.
- `[truth:source]` When documentation conflicts with implementation, the implementation and its passing proof boundary are authoritative until the documentation is corrected.

## Active Work

- [ ] [status:yellow] [truth:source] Complete Mr. Rescue: Lupi Edition as a separately licensed, full-fidelity port with original Classic mechanics and an optional child-friendly presentation mode. `demos/mr-rescue/` is explicitly authorized only as a named-board physical-validation candidate; hardware approval still requires its frame-time, memory, and soak proof.
- [ ] [status:yellow] [truth:source] Port all 100 Hex-a-Hop levels only after Mr. Rescue receives named-device approval. Preserve its undo/no-timer accessibility, isolate GPL/CC attribution, and apply the same fail-closed package and physical-device gates.
- [ ] [status:yellow] [truth:source] Close the newer provisional console-API gaps (`ui.grid`, `ui.mouse`, pressure-valued input, and Clay layout) only against executable firmware semantics; the public pinned simulator does not implement enough of that provisional documentation to support a truthful parity claim yet.

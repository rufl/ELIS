## Problem

<!-- State the user or contributor impact and link the issue when one exists. -->

## Solution

<!-- Explain the ownership boundary and important invariants, not every edited line. -->

## Verification

<!-- List exact focused commands and results. -->

- [ ] `zig fmt` was run on changed Zig files.
- [ ] The smallest relevant unit or smoke gate passes.
- [ ] `bash scripts/verify.sh` passes before review, or the missing proof is explained.

## Review boundaries

- [ ] Compatibility changes include a fixture and `COMPATIBILITY.md` update.
- [ ] External-input changes retain fail-closed path, size, count, and cleanup behavior.
- [ ] Allocations, C handles, SDL resources, and temporary files are released on error and success paths.
- [ ] Workshop changes preserve one-command gestures, undo/redo, migration, and input equivalence.
- [ ] User-visible or contributor-facing behavior is documented.
- [ ] Third-party code/assets retain their original license and attribution.
- [ ] No physical FPS, memory, controller, or hardware-approval claim is made without named-device evidence.

## Screenshots or captures

<!-- UI changes: attach isolated-display before/after captures at relevant window sizes. -->

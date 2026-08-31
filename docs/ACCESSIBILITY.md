# Accessibility

ELIS supports keyboard, mouse, and controller operation, but its current custom SDL interfaces do not expose a native accessibility tree. This document records what works and where contributors should not overclaim support.

## Current support

- Simulator menus have fixed keyboard fallbacks even when gameplay bindings are cleared.
- All twelve console actions can be remapped, with duplicate-binding feedback and reset-to-default recovery.
- Workshop's primary painting, erasing, selection, shape, layer, preview, save, and template workflows have keyboard and controller paths.
- Workshop supports `--reduce-motion`; information does not depend on guide animation.
- Focus loss clears or finalizes active input ownership. Queued keyboard, pointer, text, and button input is ignored while suspended, and a held analog stick is sampled without creating a new edge when focus returns.
- Important states use text and shape in addition to color: selection outlines, marker letters, status labels, errors, warnings, and lock/visibility labels.
- The simulator scales the exact indexed surface with nearest-neighbor pixels. Workshop has tested compact 960×600 and roomy 1280×760 compositions.

## Known limitations

- SDL-rendered controls have no VoiceOver, TalkBack, AT-SPI, or other native screen-reader semantics.
- The canonical 5×8 bitmap font and fixed logical layouts do not follow operating-system text scaling.
- Workshop requires a minimum 960×600 window; the simulator requires at least the 480×270 Lupi resolution.
- Controller coverage is source- and automation-audited, but physical-controller approval remains separate.
- Cartridge accessibility is owned by each cartridge. ELIS cannot infer captions, color alternatives, or remapping semantics for arbitrary Lua games.

These are architectural limitations, not completed accessibility claims. A contribution adding native accessibility must preserve indexed game output and should create a semantic host-control layer rather than modifying cartridge pixels.

## Reporting an accessibility problem

Open a GitHub issue with the affected screen, input method or assistive technology, window size, expected behavior, and a minimal reproduction. Report security-sensitive details privately through [SECURITY.md](../SECURITY.md).

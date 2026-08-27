# Repository Agent Rules

<!-- lichforge-display-test-policy:start -->
## Golden rule: focused and contained tests

- During implementation, run only the smallest test or test group that proves the behavior being changed. Do not run a full repository, platform, browser, device, or graphical matrix.
- Any test that needs a display must run inside a disposable isolated display environment, such as headless browser mode, Xvfb with a lightweight window manager inside a private socket namespace, or a dedicated container/VM compositor. Plain Xvfb alone is insufficient because it can still inherit host Wayland and session-bus sockets. It must never use, replace, reconfigure, capture, or inject input into the developer's active X11/Wayland session, desktop compositor, or physical monitors.
- Display-test wrappers must fail closed when isolation is unavailable. Use `overzeer-isolated-display` or a reviewed repository wrapper that provides equivalent private display/session sockets, bounded timeouts, serialized graphical runs, and complete spawned-process-tree cleanup.
- A full test matrix is allowed only as final pre-commit verification. It must still use isolated displays, remain pressure-gated and serialized, and must not run against the main display. In Pi sessions, the user must grant the one-shot `/precommit-matrix` permit first.
<!-- lichforge-display-test-policy:end -->

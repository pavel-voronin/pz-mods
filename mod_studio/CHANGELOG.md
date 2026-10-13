# Changelog

## Unreleased

### Added
- Add the main-menu game language selector transferred from pz3d, using native language settings and Lua reload.

### Maintenance

- Multiplayer scenarios: confirm current native pz3d startup through its valid signature, successful entry invocation and patch initialization while rejecting incomplete or conflicting loader evidence.

- Multiplayer scenarios: tolerate the atomic replacement gap while polling observer startup files.

- Multiplayer scenarios: optionally finish observer loading before starting the second native client to reduce overlapping startup memory without changing heap limits or the two-client protocol.

- Multiplayer scenarios: accept explicit mod checkouts and link their native packages into disposable profiles so worktree builds are tested without replacing the main checkout.

- Scenarios: inspect actual mapped lamp power and export live square lighting, source and visibility data from owned NoSave worlds. Add an explicit native-render reference mode that preserves vanilla graphics separately from loader baselines.

- Capture user F12 screenshots into the current scenario's screenshots/user folder with step metadata, independently of automated captures; preserve native F12 outside controlled scenarios.
- Allow F12 polling and key events during automated scenarios without releasing gameplay input or interrupting execution; verify the exception with transformed input regression tests.
- Scenarios: align paired-door regression fixtures with native lock and obstruction queries.
- Scenarios: integrate native streaming maps, reserve telemetry and protected diagonal fixtures with menu preparation; remove the retired capture-only bridge.
- Scenarios: unlock freshly created paired-door fixtures before native toggles and retain obstruction diagnostics.

- Lead the native artifact summary with forward readiness, missing chunk counts and observed data flow; retain frame diagnostics only in raw records.
- Record actual window/framebuffer size without requiring a graphics benchmark resolution for data-loading experiments; await nonzero framebuffer dimensions during preparation.
- Sample ready/missing chunk counts in the forward half of native demand and report attachment throughput alongside continuous route lead. Add short visible city comparisons and default the experiment runner to a window so other tasks can use the desktop.
- Keep a visible stage/countdown line during native measurement controls and preparation. HUD-off controls now retain this common minimal status line, whose drawing cost is included in HUD timing.
- Add an isolated native chunk-loader baseline with wall-clock noclip motion, explicit chunk readiness stages, update/presentation tails and buffered diagnostic samples, diagonal city/countryside routes and a prepared world-map display with live telemetry. The native player is protected before warmup; failed preparation cannot silently start a measurement. Native-only launch profiles exclude other enabled mods and preserve user settings.

- Keep generated-map preparation source free of platform-specific line-ending changes.
- Align static maps with native world-map coordinates, validate a dense city route from room metadata, and count all allocated native chunk floors.

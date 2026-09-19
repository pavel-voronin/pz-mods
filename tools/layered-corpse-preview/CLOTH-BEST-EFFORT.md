# Rendering despite unresolved contacts — 2026-09-18

The application now treats residual garment intersections as non-fatal quality
warnings, per the user's explicit request. The accepted v2 material, damping,
release times and throw solver are unchanged. Progressive dressing and the v3
rest finalizer remain disabled.

The `--allow-initial-intersections` policy is passed through preparation,
remeshing, final release-clearance checks and Blender baking. Preparation still
tries its existing bounded repairs. Counts stay in reports and cache warnings;
no garment is silently omitted, and no extra source faces are cut out.

If whole-layer separation cannot resolve contacts, retain individually repaired
positions instead of applying the maximum failed trial offset. If remesh binding
exceeds 2 cm, retain the prepared mesh with identity render binding instead.
Strict lower-level diagnostics remain available; the CLI uses best effort by
default and accepts `--strict-intersections` for diagnostic rejection.

New caches use `isotropic-damped-v2-best-effort-<sceneKey>.pzcloth`. Existing
accepted v2 caches remain readable and are not overwritten. Browser state,
model assets and saved drop locations are unchanged.

This removes contact-based blocking; it does not guarantee intersection-free
images or mask actual missing files, invalid arrays, broken bindings, process
failures or resource exhaustion. Residual visual artifacts remain possible.

Regression source: job `5982ae43-ddfc-4aa7-968c-cf06b5f84677`, six garments,
whose fifth garment had 72 prepared intersections. End-to-end output is kept
separately in `outputs/best-effort-regression-20260918`.

Completed verification: all six garments, 415 frames, 487.86 s native bake;
initial/held render delta zero. Decode succeeded and the real service returned
ready and served the registered cache (job d6577c67-d3eb-41a7-b16b-d2a630f09121).
Remaining visual-quality warnings are not suppressed: 176 final intersection
pairs and residual motion. These no longer prevent playback/export. No claim
of visually intersection-free cloth is made by this change.

Backup: `outputs/checkpoints/before-best-effort-20260918`.
Test: Blender `--python scripts/test-best-effort-cloth.py`, plus TypeScript
no-emit and the existing cache/service tests.

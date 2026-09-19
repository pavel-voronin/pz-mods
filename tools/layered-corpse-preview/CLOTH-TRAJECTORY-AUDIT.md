# Release/contact regression, 2026-09-16

The failing user scene is preserved in `outputs/blender-jobs/19717d73-dadd-49cd-a779-b5e840aba22e` (scene key `84cb28dc603af8462e816f898c78ef3f7d2a972b90bad8b7551ec3795c745f83`). Five garments, 349 frames. Do not replace the source fixture or its original cache.

## Evidence

- Original final centroid speeds: 0.0011, 0.0776, 0.8565, 0.9052, 0.1887 scene units/s. The trousers and jumper accelerate after landing; this is not just an incorrect ballistic target or a camera/render transform.
- Source launch velocities are approximately (-0.6, +2.6, -0.7). The cloth cache itself contains the runaway motion. `scripts/audit-cloth-trajectory.mjs` measures it without browser playback.
- `scripts/audit-cloth-launch.py` tests pin release on a free triangle: input horizontal velocity 1 produces 1, and the configured time scale gives gravitational acceleration approximately 9.81. The launch is not multiplied by FPS or the Blender time scale.
- Per-item preparation reports zero self-crossings, but the simultaneous trousers/jumper layer contains 391 refined triangle crossings (97 coarse crossings). `scripts/audit-cloth-overlaps.py` exposes this missing precondition. Other release times must not be treated as simultaneous physical contacts while still pinned.
- The original single-garment diagnostic changed particle mass when isolating a garment. `cloth-launch-audit.py` now preserves the full-scene numerical particle mass and labels this explicitly in the report; do not compare the earlier isolated trial as a controlled A/B test.

## Candidate being evaluated

`prepare-cloth-scene.py --posed-shell --repair-layers` keeps each repaired garment's topology, UVs and dimensions. It separates overlapping simultaneous-release islands along their existing relative layout, bounded to 122 mm per island and only if crossings exist. This scene needs 37 mm per island. The existing 0.18 s render-offset blend preserves the exact dressed pose and introduces the separation smoothly after removal. It does not create springs between garments, shrink geometry, clamp an already computed trajectory, or disable contacts after landing.

`test-layer-preparation.py` verifies the refined release layer, unchanged render starts/UVs/topology, and a uniform translation rather than a deformation of each garment. This preparation test passes on the user fixture. A full-motion and visual test is required separately; zero initial crossings alone does not establish that the resulting animation is good.

## Controlled tests and rejected candidates

- Layer separation alone: 96 final crossings, 23 mm maximum floor penetration, final centroid speeds up to 0.53 units/s. Rejected as a complete fix; not installed into the user's cache.
- Isolated trousers, matching full-scene particle mass 0.314340949: angular bending gives tail RMS 0.33899 and centroid speed 0.20451. Disabling bending alone gives 0.01113 and 0.00386. Mass is identical in this comparison.
- Quad patches + LINEAR bending 0.05 on the same isolated fixture: tail RMS 0.06168, centroid 0.01292. This removes the angular rest-curvature goal. The full scene candidate uses a lighter default 0.005, still with all collision responses enabled.
- Separate mutually colliding Cloth modifiers produced Blender dependency cycles. That prototype was rejected and removed, not promoted as a fix. The shared contact solver is retained.
- A free-flight probe with air damping 2 confirms substantial damping of the planned ballistic throw. Landing accuracy must be checked as well as late motion; `test-cloth-landing.mjs` rejects the original cache (up to 2.03 units layer-target error and 0.45 units travel in the final half-second).
# Accepted trajectory regression — isotropic-surface-v1

Fixture: `outputs/trajectory-audit/isotropic-aim`. Five garments, 349 frames,
3602 physical vertices (8638 rendered particles), 289.63 seconds.
Same source scene as original failing job `19717d73-dadd-49cd-a779-b5e840aba22e`.

Final half-second centroid displacement: 6.03 / 2.44 / 0.434 / 0.175 / 0.078 mm.
Original trousers/jumper travelled 424 / 450 mm in that interval.
Layer center landing errors: 39 / 14 / 110 mm; the predeclared 150 mm test passes.
This measures layer centers, not containment of every vertex in a target circle.
Initial and held-pose error zero. Maximum floor penetration 0.346 mm.

Remaining limitation: 181 final triangle intersections and nonzero local flutter.
Do not describe this as intersection-free cloth or a certified cotton material.
The fix addresses scene-wide runaway, mesh conditioning and drag-aware launch.
No late freezing, attraction, cache translation or pressure was used.

Browser verification: the unchanged persisted five-garment scene loaded this cache
through «Рассчитать в Blender» automatically (349 frames, 181-intersection warning,
not the old 382-intersection cache). Played to «Готово»: all clothes visible behind
the body, trousers and jumper remain recognizable, no off-screen runaway.
The app render is authoritative for textures; Workbench inspection renders did not
faithfully display all garment textures. Server remains available at localhost:3000.

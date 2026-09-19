# Cloth audit — 2026-09-15

This is a diagnosis, not a completed cotton preset. Production settings were not changed during this audit.

## Reproducible controls

Run `scripts/cloth-panel-audit.py` with Blender in background mode, passing an output directory after `--`. This isolates a 0.5 m panel from body collisions, launch keys, pins and imported geometry. The scene runs for six seconds at 60 fps; measurements cover the last second.

| Case | RMS vertex speed (m/s) | Centroid speed (m/s) |
| --- | ---: | ---: |
| Panel, bending damping 2 | 0.000138 | 0.000022 |
| Panel, bending damping 0.005 | 0.000112 | 0.000019 |
| Panel, bending damping 0 | 0.000865 | 0.000108 |
| Valid prepared trousers, gravity drop without launch/body | 0.001921 | 0.000437 |

For the last case use `--garment PATH_TO_scene-prepared.json 2`. Results: `outputs/cloth-panel-audit/report.json` and `outputs/cloth-isolated-pants-audit/report.json`.

`scripts/cloth-launch-audit.py` takes a prepared scene, output directory and item index. It runs the production launch for that item without the body or other garments. The cache deliberately has an incompatible scene key and must not replace an app bake. Trousers, six-second scene: last-half-second RMS 0.015330 m/s, centroid 0.004726 m/s, no final triangle intersections or floor penetration. Results: `outputs/cloth-launch-audit/scene-bake-report.json`.

These are not strictly matched A/B measurements: the gravity-only case starts 0.35 m above the floor at time zero; production launch starts in the app pose at its original release time. They establish achievable settling, not the isolated causal contribution of launch velocity. No visual cotton-quality claim follows from low tail speed.

## Confirmed implementation deficiencies

- `blender-scene-bake.py` uses a constant numerical mass of 0.3 per vertex. Refining the surface changes the total numerical mass. There is no area-based material calibration or resolution-invariance test.
- Without an effective rest-shape override, Blender builds rest lengths and angular rest values from the starting surface. Here that is the skinned pose, not an unstressed garment pattern.
- Refining triangles preserves the source metric and defects; it is not a reconstruction of sewing patterns. The current shirt has 16 original / 40 refined initial triangle-pair intersections.
- Edge-length difference between prepared bind and posed surfaces: median / 90th percentile / maximum absolute relative change is 2.22% / 10.78% / 26.82% for underwear, 2.57% / 18.84% / 90.25% for shirt, and 1.65% / 10.17% / 37.61% for trousers. These are geometric skinning changes, not measured elastic strain of real fabric.
- Mass, spring stiffness, collision distance and solver time have not been jointly calibrated as a cotton material. Earlier damping/friction experiments did not establish such a calibration.

## Rest-shape test remains unresolved

`--rest-comparison` compares an initially curved developable panel with its isometric flat rest shape. Both runs produced identical aggregate measurements. Even `--metric-control`, which deliberately doubles rest dimensions, produced identical results; updating data and `--reload` did not change that. This test therefore does **not** demonstrate that the rest-shape override is effective in this harness. It must be debugged before relying on that mechanism for a fix. Do not attribute all observed crawling to rest curvature based on this result.

## Required correction path

1. Keep the working visible body/garment rig and exact app snapshot unchanged.
2. Establish a physical surface with a verified material-space metric and bending rest state; separate it from the game render surface. Resolve initial self-intersections before accepting a presentation bake.
3. Calibrate total mass versus area, stretching, bending and dissipation on panel tests and at two mesh resolutions. More vertices must improve convergence, not change the material.
4. Test one real garment: drop, then production launch, then body contact, then multiple garments. Match release times and initial heights when making causal comparisons.
5. Verify that launch only supplies initial momentum and that post-impact energy decays without artificial freezing or shape/volume goals. Keep all detached items mutually colliding.
6. Transfer simulated motion to the textured render surface and return the existing vertex cache automatically. No new application installation is required for this architecture.

References: Blender 5.1.2 `cloth.cc` (rest lengths/angles), `SIM_mass_spring.cc` (force/time scaling), `implicit_blender.cc` (angular forces); Baraff & Witkin 1998, Bridson et al. 2002/2003 for thin-surface cloth, bending and contact.

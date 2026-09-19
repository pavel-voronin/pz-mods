# Residual cloth motion — 16 September 2026

Baseline: `outputs/trajectory-audit/isotropic-aim`, preserved unchanged.
All candidate work is under `outputs/settling-audit`; production v1 remains active
until the full-scene settling AND trajectory regressions pass.

## Findings

No wind or pressure object exists in the bake. Launch keys stop changing after
release+1; pin weights are asserted off after release+2. Pocket items are not in
the Blender solve, so they cannot inject energy into this cache.

Blender's LINEAR bending implementation does **not** use `bending_damping` as a
velocity damper: it multiplies the elastic `cb` branch of `fbstar`, and the velocity
Jacobian is zero. Increasing this parameter can change the spring force instead
of dissipating motion. Sources:
[force construction](https://raw.githubusercontent.com/blender/blender/blender-v5.1-release/source/blender/simulation/intern/SIM_mass_spring.cc),
[implicit solver](https://raw.githubusercontent.com/blender/blender/blender-v5.1-release/source/blender/simulation/intern/implicit_blender.cc).

Self-contact uses penetration-correction and stopping impulses. An isolated bra
with the same particle mass and throw has tail RMS 17.15 mm/s; disabling self-contact
gives 2.40 mm/s but 142 crossings, so disabling contacts is NOT a fix.
This establishes contact contribution, not that every residual wave is numerical.
Real fabric can transmit a disturbance; the target is decay, not banning propagation.

## Controlled isolated tests

All use the same 123-point remesh, numerical particle mass 0.7310531, six-second
timeline, launch and air=2 unless stated otherwise. Baseline full-scene average
spring length is not preserved by isolation, so use these to compare isolated
variants, not to claim precise full-scene attribution.

| Variant | Tail RMS mm/s | Final triangle crossings |
|---|---:|---:|
| baseline | 17.15 | 0 |
| contacts: steps 48 / collision passes 24 | 7.68 | 7 |
| structural damping 50 | 12.59 | 8 |
| both | 13.27 | 8 |
| both + self friction 60 | 12.44 | 1 |
| air 10 + compensated launch | 20.70 | 0 |
| no bending | 24.44 | 9 |
| ANGULAR weak elasticity, true damping 0.5 | 6.34 | 4 |
| ANGULAR zero elasticity, true damping 2 | 2.44 | 0 |
| ANGULAR weak elasticity, true damping 2 | 4.36 | 10 |
| ANGULAR weak elasticity, true damping 8 | 1.98 | 0 |

The apparent .25 mm self-distance experiment was clamped to 1 mm by Blender RNA
and is identical to the contacts variant; it is not evidence for thickness changes.
The initial full-scene bending_damping=20 trial was cancelled after source review.

## Acceptance

`test-cloth-settling.mjs BASELINE CANDIDATE`: identical scene identity, UVs,
render topology and launch velocities; first 150 ms centroid difference <10 mm;
final horizontal centroid displacement relative to accepted v1 <80 mm;
tail RMS <12 mm/s and 95th-percentile late excursion <6 mm per garment.
`test-cloth-landing.mjs` still checks the existing pile target and late centroid drift.
These tolerances were written before full candidate results, not fitted afterward.
No post-bake smoothing, frozen tail, position clamping, or attraction is used.

## Full-scene results (five-garment regression)

- Increasing steps 24→48 and contact iterations 12→24 alone **failed**:
  tail RMS 122/106/52/62/73 mm/s, worse than baseline 85/78/34/22/32.
  Isolated results did not generalize to the interacting pile. Not promoted.
- True angular damping 2 with zero angular elasticity: RMS
  19.4/12.1/5.49/5.79/5.37 mm/s. This confirms a useful dissipative mechanism,
  but fails the declared settling threshold on the small last-released clothes.
  Also removes the material bending-stiffness distinction, so remains diagnostic.
  Launches/UVs are identical; early centroid differences ≤0.121 mm, and the
  established pile-target regression passes.

Current user scene: job `90e33ee5-4b30-443a-aef8-0ea24c256a12`, four garments,
key `79c2106ae186f8ec96fe7e2828d15194d1946d2856ba069a2dd1bd6c39d7be7d`.
Original tail RMS 119.7/69.9/21.0/30.6 mm/s. Preserve this fixture and user selection.

Weak angular elasticity + damping 2 (five garments) yielded RMS
12.22/11.38/4.60/8.96/8.25 mm/s and 65 final crossings (baseline 181).
Not accepted as fully settled: first item slightly exceeds 12 mm/s and the second
has 7.02 mm P95 excursion versus the 6 mm bound. Launch is identical; maximum early
center deviation is 0.140 mm. This keeps the per-garment stiffness group active,
unlike the zero-elasticity diagnostic.

The newer four-item baseline already misses the 150 mm absolute pile test on
layer 0 (198 mm) before these changes. Do not weaken that test or attribute this
pre-existing placement to settling. Compare unchanged launch and landing drift
against this baseline as well as running the absolute test in report-only mode.

## Post-remesh input bug

Four-item scene: preparation checked release layers BEFORE MeshLab, but the final
remeshed underwear/T-shirt layer has **411 crossings**. Its pre-remesh report says
zero. The final mesh, not this old report, must be checked. Damping 8 without fixing
these crossings still gives 53.6/22.4 mm/s on those two items.

`cloth-release-clearance.py` now checks after remeshing, rigidly separates only an
invalid/near-contact release layer, and requires zero crossings and 2.2 mm sampled
vertex/surface clearance. This scene needs opposing 27 mm offsets (common layer
center unchanged); final gap is 2.587 mm. UVs, topology, original render starts and
launch velocities remain unchanged. `test-release-clearance.py` verifies bounded
rigid translation and idempotence. The bake also rejects crossed release layers.

For this newly identified repair, trajectory regression reports BOTH raw early
center difference and the difference after subtracting the prescribed static
clearance blend. The 10 mm dynamic-flight bound stays unchanged; repair is bounded
separately to 50 mm. Launch comparison allows 1e-6 float roundoff from rigidly
translated area calculations, not a different planned velocity. The five-item
regression needs no added repair and passes the original unchanged flight bound.

## Passing five-item material profile

Weak ANGULAR elasticity + actual angular damping 8, zero compression spring:
tail RMS 7.52/9.44/2.60/2.19/2.25 mm/s; P95 late excursions
4.07/4.88/1.90/1.66/1.58 mm. Both settling and existing landing tests PASS.
No floor penetration; 72 final triangle intersections (not intersection-free).
Quality remains 24/12, air remains 2. Per-item stiffness weights remain active.

## Accepted current scene / qualification of trajectory comparison

`outputs/settling-audit/current-repaired`, revision `isotropic-damped-v2`:
358.42 seconds, unchanged 3260 simulation vertices, 349 frames. Final RMS
6.29/4.37/3.02/3.16 mm/s; P95 late excursion 3.91/2.53/1.99/2.04 mm.
Zero measured floor penetration; final crossings 86 (baseline 228).
Settling thresholds pass, initial/held pose deltas zero, launch values identical.

The relative-to-broken-cache trajectory test **does not pass** on the repaired
underwear/T-shirt: eliminating the erroneous contact kick shifts their final
centers 325/107 mm. Early residual difference is up to 13 mm. Do not hide this
failure or claim exact old trajectories. The user's intended target is preserved:
layer-center error drops from 198 to 12 mm, and the original absolute pile-target
test passes unchanged for all layers (12/10/88 mm). The five-item unaffected-source
test passes BOTH relative trajectory and settling checks. Current input uses
`--settling-only` plus the independent absolute landing test; this bypasses ONLY
comparison to the corrupt reference trajectory, explicitly reported in output.

Production service and CLI use `--surface-fabric --drag-aware-launch --damped-fabric`.
Old v1 caches and all reference inputs remain intact. No material-quality increase
or rendering smoothing is needed; the installed correction is physical damping
plus final-input collision repair.

Browser verification completed: unchanged current four-item selection loaded v2
automatically through the existing Blender button (349 frames, 86-crossing warning).
Played to «Готово»: clothes form the rear pile, no off-scene pieces, recognizable
shirt/trousers, body and loot unchanged. The warning about continuing cloth motion
is absent; the honest intersection warning remains. Server is running on port 3000.

# Residual waves after accepted v2 — 2026-09-16

Production source and accepted caches are preserved in
`outputs/checkpoints/accepted-damped-v2-20260916-152343/` (178 hashed files).
The accepted native v2 physics and launch parameters remain unchanged. Production
now applies the explicit whole-pile rest finalizer described below.

## Shipped fix: isotropic-rest-v3

Two distinct changes:

1. `app/cloth-normals.ts`: replace the abrupt face-neighbour rejection at 90°
   with continuous smooth weighting. Tiny geometric changes no longer switch
   an entire face's shading contribution on/off. No temporal normal filtering.
2. `scripts/finalize-cloth-rest.ts`: offline whole-pile sleeping, not a new
   material model or proof that Blender has reached exact static equilibrium.
   After every release and flight, require 0.25 s of small per-garment motion
   (window RMS <12 mm/s, mean centroid speed <4 mm/s, each vertex step <3 mm).
   Require proximity to the floor and inspect the remaining native trajectory
   to reject a pause before a later impact/slide. Keep ONE complete native frame
   for the entire pile thereafter; no independent vertex/garment correction.
   If the conditions are not met, keep the native simulation and issue a warning.

This is a presentation-cache approximation. It deliberately discards residual
low-energy motion; it does not claim to identify the exact energy source or
eliminate all native cloth/contact defects. All frames through sleep are bit-for-bit
unchanged. Existing interpenetrations are neither repaired nor newly introduced by
mixing frames: all garments retain their original common snapshot. The native
last-frame intersection count is retained as `nativeFinalIntersections`, not
misreported for the earlier retained frame. The original tail velocities are
retained as `nativeTailMotion`.

Regression fixtures (13 garments total):

| Scene | Sleep time | Final half-second RMS / excursion | Largest landing-centre change |
| --- | ---: | ---: | ---: |
| current-repaired | 4.50 s | 0 / 0 | 0.50 mm |
| 77878d3f newer | 3.55 s | 0 / 0 | 1.10 mm |
| strong, five garments | 5.033 s | 0 / 0 | 1.42 mm |

`test-cloth-rest-fixtures.mjs` checks every coordinate before sleep and the shared
snapshot afterwards. 17 unit tests, strict-rest tests on all three fixtures,
TypeScript, cache validation, and local service tests pass. A service POST using
the old accepted cache returned a v3 cache without starting Blender.

The browser button and CLI both invoke this finalizer. The server uses a new
`isotropic-rest-v3-` cache namespace and can safely upgrade v2 caches without
overwriting them. Manually imported raw old caches are not silently modified.

Rejected trials remain under `outputs/settling-audit/` for reproducibility:
relative damping (unstable), contact-local output relaxation (more intersections),
double solver quality (945 s with residual motion), in-plane compression and
post-impact drag (better area retention but still residual motion). None of these
experimental settings are enabled in production; experimental flags were removed.

The following sections document the investigation before this finalizer.

## Measurements

`node scripts/audit-cloth-decay.mjs outputs/settling-audit/current-repaired`
measures RMS velocity over half-second windows directly from the vertex cache.
It separates mean translation from residual motion (deformation plus any rotation).
This metric is sqrt(mean(speed²)), unlike the historical report's mean per-frame RMS.

| Item | RMS 4.3–4.8 s | RMS 4.8–5.3 s | RMS 5.3–5.8 s | Final centroid RMS |
| --- | ---: | ---: | ---: | ---: |
| 0 | 8.63 | 5.53 | 6.64 | 1.12 |
| 1 | 6.90 | 6.52 | 4.44 | 0.44 |
| 2 | 3.57 | 2.89 | 3.04 | 0.38 |
| 3 | 3.86 | 3.96 | 3.18 | 0.27 |

Units: mm/s. This is not a proof of energy generation: gravitational potential,
elastic energy and contact work are not measured by a velocity-only audit.
However, visible late motion is real, not merely playback interpolation or lighting.
The last release is 3.3 s; the recorded sequence ends at 5.8 s. Indefinite non-decay
cannot be inferred from that short tail.

The user's newer job `77878d3f-4fd0-4979-8859-40adb5aaf248` completed independently
while this investigation ran. It was not interrupted. Its last-window RMS values
are 12.40, 4.42, 3.21, 4.99 mm/s; item 0 rose from 6.59 in the preceding window.
Its cache is also preserved in the checkpoint.

## Code findings

- Playback only interpolates cached positions (`sampleCloth`); no added flutter.
- No wind/pressure/internal springs; launch shape keys stop changing after one
  frame and pins are checked off after release.
- ANGULAR bending still has weak rest-angle elasticity (.0001–.0025 bounds,
  .0005 at the default garment weight), with velocity damping 8.
- Stretch/shear springs remain. Zero bend stiffness is not zero total elasticity.
- Contact response includes separating impulses for penetration/proximity,
  not merely friction. This is a plausible source of low-level contact chatter.
- Warning threshold 20 mm/s and regression allowance 6 mm excursion were too
  permissive to certify visually still cloth. Passing those checks is not rest.

Primary sources: [Blender force construction](https://raw.githubusercontent.com/blender/blender/blender-v5.1-release/source/blender/simulation/intern/SIM_mass_spring.cc)
and [contact response](https://raw.githubusercontent.com/blender/blender/blender-v5.1-release/source/blender/blenkernel/intern/collision.cc).

## Controlled comparison

Trial directory: `outputs/settling-audit/current-no-rest-elasticity`.
Source and prepared geometry copied unchanged from `current-repaired`.
Flags: `--surface-fabric --drag-aware-launch --settle-viscous --settle-strong`.
Only angular elastic stiffness becomes zero; damping stays 8, air 2, all launch
and collision settings remain the same. This is a diagnostic cache, not promoted
to the application.

### Result

386 s, same 3260 physical vertices, 349 frames. Prepared inputs identical.
Historical report metric (mean per-frame RMS), mm/s:

| Item | Accepted | No angular elasticity | Reduction |
| --- | ---: | ---: | ---: |
| 0 | 6.294 | 5.316 | 15.5% |
| 1 | 4.374 | 4.159 | 4.9% |
| 2 | 3.024 | 2.708 | 10.5% |
| 3 | 3.155 | 2.656 | 15.8% |

The rest-angle spring contributes but removing it does NOT remove the waves.
Do not attribute all remaining movement to memory of the dressed shape.
Final centroid displacement from the accepted cache is at most 1.29 mm;
source/compensated launch vectors and render topology/UVs match, early trajectory
delta <0.019 mm. Existing regression passes but does not certify visual stillness.
P95 tail excursion remains 1.59–3.44 mm. Contact crossing diagnostic goes 86→36;
native solver uses joined quads whereas this counter uses source triangles, so
the count is not an exact inventory of native contact defects.

Leading remaining hypothesis: low-level contact correction combined with
stretch/shear spring response, rather than wind or the launch. Earlier isolated
self-contact-on/off tests support contact contribution, but this full-scene
comparison alone does not separate contact impulses from elastic/gravitational
energy release. A force-level or matched contact diagnostic is required before
claiming a unique root cause. Increasing mesh resolution or global drag blindly
is not justified by these measurements.

Recommended next implementation investigation: contact-local dissipative response
and a longer post-impact diagnostic tail, with unchanged launch and no arbitrary
whole-garment freezing. No such physics change was silently installed here.

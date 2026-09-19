# Progressive preparation experiment — 2026-09-17

Status: **experimental, not promoted to the application default**. The whole
pipeline is not yet a successful general replacement. No accepted cache was
overwritten. The existing button still runs the accepted preparation/bake path.

## Implemented

- Snapshot export contains raw meshes, skin weights, inverse bind matrices,
  current bone transforms and preparation-only spread-leg bind transforms.
- A separate approximately 18 mm isotropic physical surface is generated from
  the unposed source. The render mesh/UVs are retained by barycentric binding.
- Local joint transforms are interpolated hierarchically. Global matrix
  interpolation was rejected: it caused a sleeve/body snag with a 97 mm error.
- Joint-attached fitted capsules and the floor participate in preparation.
  Capsules are an approximation, **not a proof of clearance against every
  triangle of the rendered body**.
- IPC contact barriers and continuous collision detection constrain each
  accepted Newton step. Every completed pose step is also intersection-checked.
- The resulting positions become the new rest positions; preparation has no
  velocities to transfer. Existing Blender release times and launch code remain.
- The CLI has an opt-in `--progressive-pose` path. No automatic fallback cuts,
  Boolean unions, source-face deletion, or silently skipped garments were added.

## Measured results

Fixture: original failing snapshot from job
`3f9320c0-f8df-4367-b821-d3f343bb5b6d`, stock front pose, Tomb body,
briefs / long sleeve shirt / trousers / vanilla suit jacket.

The explicitly labelled three-item subset excludes the jacket **for diagnosis**;
it is not presented as a successful four-item scene.

`outputs/progressive-hierarchy-three-20260917`:

- 2,333 cloth particles, 48 preparation steps, 39.37 s total preparation.
- No detected preparation intersections. CCD constrains motion between steps.
- Maximum render transfer deviation: briefs 3.27 mm, shirt 12.72 mm,
  trousers 5.31 mm; 95th percentile at most 3.59 mm.
- Subsequent native Blender bake: 283 frames, 153.76 s, exact initial/held
  rendered positions, floor penetration 0.617 mm.
- **Rejected final quality:** 58 intersecting triangle pairs at the last frame,
  residual motion remains. The accepted numerical-sleep finalizer was NOT used
  to hide these findings. Successful numerical solver status does not mean
  collision-free fabric.

## Unresolved blockers

1. Full four-item initialization: each source garment is individually clean,
   but their canonical arrangement is not mutually intersection-free. The
   jacket conflicts with the inner garments/body. Normal offsets and uniform
   expansion were tested and rejected; they are not a general dressing method.
2. Blender's subsequent discrete collision solve can reintroduce intersections
   even after clean preparation. Increasing mesh density alone is not proven
   to fix it. The CCD guarantee currently ends at the preparation boundary.
3. The preparation chain is an explicit app-compatible joint chain, not an
   extracted authoritative game hierarchy. Unknown joints fail, not guess.
4. Some constrained steps reach the iteration cap. Their convergence flags are
   retained in the report; no claim of exact static equilibrium is made.

Next implementation work must address both the initial layered embedding and
collision preservation during release. Do not enable the UI path or reuse the
accepted cache namespace before these pass on the full fixture.

## Reproduction

From the project directory, using a newly exported snapshot:

```powershell
node --experimental-strip-types scripts/bake-blender-scene.mjs SNAPSHOT.json --out outputs/progressive-trial --progressive-pose
```

Optional dependencies are pinned in `scripts/requirements-cloth-progressive.txt`
and installed into `.cloth-deps` for Blender's bundled Python, not global Python.
The standalone preparation entry point is `scripts/progressive-cloth-pose.py`.
The offline `upgrade-pose-fixture.mjs` only accepts an exactly matching stock
pose; it rejects custom ragdoll snapshots instead of reconstructing them falsely.

Tests: TypeScript no-emit; `scripts/test-progressive-pose.py` under Blender
(CCD detects tunnelling missed by endpoint checks, bounded collider drift,
hierarchical joint-length preservation and exact endpoint transforms).

## Rollback

The accepted checkpoint `outputs/checkpoints/accepted-damped-v2-20260916-152343`
remains untouched. The additional source backup is
`outputs/checkpoints/before-progressive-pose-20260917`.
Experimental output directories are separate from `outputs/cloth-cache`.

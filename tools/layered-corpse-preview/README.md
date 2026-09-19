# Layered Corpse Preview

Local Project Zomboid scene editor: zombie poses/ragdoll, clothing removal,
pocket-item physics, Blender cloth baking and GIF export.

## Run

Requires Node.js >= 22.13 and pnpm. From this directory:

```powershell
pnpm install --frozen-lockfile
pnpm dev --host 127.0.0.1 --port 3000
```

Open http://localhost:3000. Some models/textures are served from the locally
installed game; the default is
`C:/Program Files (x86)/Steam/steamapps/common/ProjectZomboid`.
Set `PZ_GAME_ROOT` to override it. Blender cloth workflow is described in
[BLENDER-CLOTH.md](BLENDER-CLOTH.md).

## Checks

```powershell
node node_modules/typescript/bin/tsc --noEmit
node --test scripts/loot-resting.test.mjs scripts/loot-ground.test.mjs scripts/loot-thin-pair.test.mjs scripts/loot-pile.test.mjs scripts/loot-landing.test.mjs scripts/axe-surface.test.mjs
```

Tests that load original item models require the installed game.
Dependencies, render outputs, simulation caches and historical checkpoint
directories are not committed. Historical audit documents may reference those
local outputs or the original development directory.

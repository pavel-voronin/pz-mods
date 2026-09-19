import { sites } from '@openai/sites-vite-plugin';
import tailwindcss from '@tailwindcss/postcss';
import vinext from 'vinext';
import { defineConfig } from 'vite';
import { createReadStream, existsSync } from 'node:fs';
import type { IncomingMessage, ServerResponse } from 'node:http';
import { join } from 'node:path';
import hostingConfig from './.openai/hosting.json';
import pocketCatalog from './app/pz-pocket-loot.json';
import {localBlenderBake} from './scripts/blender-service';

const SITE_CREATOR_PLACEHOLDER_DATABASE_ID =
  '00000000-0000-4000-8000-000000000000';

const { d1, r2 } = hostingConfig;

// macOS Seatbelt blocks FSEvents, so Codex previews need polling for HMR.
const isCodexSeatbeltSandbox = process.env.CODEX_SANDBOX === 'seatbelt';

const gameRoot =
  process.env.PZ_GAME_ROOT ??
  'C:/Program Files (x86)/Steam/steamapps/common/ProjectZomboid';

function localProjectZomboidAssets() {
  const assets = new Map<string, string>();
  const worldModelRoot = join(gameRoot, 'media', 'models_X', 'WorldItems');
  const weaponModelRoot = join(gameRoot, 'media', 'models_X', 'weapons');
  const textureRoot = join(gameRoot, 'media', 'textures');
  const gameAssets: Record<string, string> = {
    '/pz-game/models/fireaxe-head.fbx': join(worldModelRoot, 'Fireaxe_Head.fbx'),
    '/pz-game/models/axe-handle.fbx': join(worldModelRoot, 'WoodAxe_Handle.fbx'),
    '/pz-game/models/handaxe.x': join(weaponModelRoot, '1handed', 'HandAxe.x'),
    '/pz-game/models/wallet.fbx': join(worldModelRoot, 'Wallet.fbx'),
    '/pz-game/models/money.fbx': join(worldModelRoot, 'MoneyStack.fbx'),
    '/pz-game/models/cigarettes.fbx': join(worldModelRoot, 'CigarettePack.fbx'),
    '/pz-game/models/lighter.fbx': join(worldModelRoot, 'LighterDisposable.fbx'),
    '/pz-game/textures/fireaxe.png': join(textureRoot, 'weapons', '2handed', 'FireAxe.png'),
    '/pz-game/textures/axe-handle.png': join(textureRoot, 'weapons', '2handed', 'WoodAxe_Forged.png'),
    '/pz-game/textures/handaxe.png': join(textureRoot, 'weapons', '1handed', 'HandAxe.png'),
    '/pz-game/textures/wallet.png': join(textureRoot, 'WorldItems', 'Wallet_Hide.png'),
    '/pz-game/textures/money.png': join(textureRoot, 'WorldItems', 'MoneyStack_1Dollar.png'),
    '/pz-game/textures/cigarettes.png': join(textureRoot, 'WorldItems', 'CigarettePack.png'),
    '/pz-game/textures/lighter.png': join(textureRoot, 'WorldItems', 'LighterDisposable.png'),
  };
  Object.entries(gameAssets).forEach(([route, path]) => assets.set(route, path));
  Object.values(pocketCatalog.items).forEach((item) => {
    assets.set(item.model, join(gameRoot,item.modelFile));
    assets.set(item.texture, join(gameRoot,item.textureFile));
  });

  const middleware = () => (req: IncomingMessage, res: ServerResponse, next: () => void) => {
    const pathname = new URL(req.url ?? '/', 'http://localhost').pathname;
    const asset = assets.get(pathname);
    if (!asset || !existsSync(asset)) {
      next();
      return;
    }
    res.setHeader('Content-Type', pathname.endsWith('.png') ? 'image/png' : 'application/octet-stream');
    res.setHeader('Cache-Control', 'no-store');
    createReadStream(asset).pipe(res);
  };

  return {
    name: 'local-project-zomboid-mods',
    configureServer(server: { middlewares: { use: (handler: ReturnType<typeof middleware>) => void } }) {
      server.middlewares.use(middleware());
    },
    configurePreviewServer(server: { middlewares: { use: (handler: ReturnType<typeof middleware>) => void } }) {
      server.middlewares.use(middleware());
    },
  };
}

const localBindingConfig = {
  main: 'vinext/server/fetch-handler',
  compatibility_flags: ['nodejs_compat'],
  d1_databases: d1
    ? [
        {
          binding: d1,
          database_name: 'site-creator-d1',
          database_id: SITE_CREATOR_PLACEHOLDER_DATABASE_ID,
        },
      ]
    : [],
  r2_buckets: r2
    ? [
        {
          binding: r2,
          bucket_name: 'site-creator-r2',
        },
      ]
    : [],
};

export default defineConfig(async () => {
  // Keep Wrangler and Miniflare state project-local. These are non-secret tool
  // settings; application environment belongs in ignored `.env*` files.
  process.env.WRANGLER_WRITE_LOGS ??= 'false';
  process.env.WRANGLER_LOG_PATH ??= '.wrangler/logs';
  process.env.MINIFLARE_REGISTRY_PATH ??= '.wrangler/registry';

  // Wrangler snapshots its log path while the Cloudflare plugin is imported.
  const { cloudflare } = await import('@cloudflare/vite-plugin');

  return {
    css: { postcss: { plugins: [tailwindcss()] } },
    server: { watch: {
      // Solver output is not application source. Watching files while Blender
      // writes them caused EBUSY crashes on Windows and unnecessary HMR reloads.
      ignored: [
        `${process.cwd().replaceAll('\\','/')}/outputs/**`,
        `${process.cwd().replaceAll('\\','/')}/.cloth-deps/**`,
        `${process.cwd().replaceAll('\\','/')}/public/cloth-rest-review/**`,
      ],
      ...(isCodexSeatbeltSandbox ? { useFsEvents: false, usePolling: true } : {}),
    } },
    plugins: [
      localBlenderBake(),
      localProjectZomboidAssets(),
      vinext(),
      sites(),
      cloudflare({
        viteEnvironment: { name: 'rsc', childEnvironments: ['ssr'] },
        config: localBindingConfig,
      }),
    ],
  };
});

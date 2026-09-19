import { bakeCloth, type ClothBakeInput } from './cloth-physics';
import { bakeLoot, type LootBodyInput } from './loot-physics';

self.onmessage = (event: MessageEvent<ClothBakeInput & { loot: LootBodyInput[]; quality?:'quick'|'precise'; reuseLoot?:ReturnType<typeof bakeLoot> }>) => {
  try {
    const bake = bakeCloth(event.data, (progress) => self.postMessage({ progress }),event.data.quality??'precise');
    const loot = event.data.reuseLoot??bakeLoot(event.data.loot, event.data.floor, event.data.duration);
    const buffers = bake.tracks.flatMap((track) => [track.positions.buffer, track.uvs.buffer, track.indices.buffer, track.particleForVertex.buffer, track.frames.buffer]);
    self.postMessage({ bake, loot }, { transfer: [...buffers, ...loot.frames.map((frame) => frame.buffer)] });
  } catch (error) {
    self.postMessage({ error: error instanceof Error ? error.message : String(error) });
  }
};

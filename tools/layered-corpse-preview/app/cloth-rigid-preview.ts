import { bakeCloth, type ClothBake, type ClothBakeInput } from './cloth-physics.ts';
import { bakeLoot, type LootBake, type LootBodyInput } from './loot-physics.ts';

export type QuickPreview = ClothBake & { loot: LootBake };

/** Original-resolution XPBD cloth with reduced substeps and approximate contacts.
 * Same release impulses and bending law as the explicit final bake.
 * No garment boxes, scaling or rigid animation.
 */
export function bakeQuickPreview(input: ClothBakeInput & { loot: LootBodyInput[] }): QuickPreview {
  return {...bakeCloth(input,undefined,'quick'),loot:bakeLoot(input.loot,input.floor,input.duration)};
}

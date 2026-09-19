import tombManifest from './pz-tomb-models.json' with { type: 'json' };

export type ModelSet = 'vanilla' | 'tomb';
type Sex = 'm' | 'f';
const replacements: Record<Sex, Record<string, { url: string }>> = tombManifest.models;

export function rigAssetSource(name: string, sex: Sex, modelSet: ModelSet) {
  return modelSet === 'tomb' && replacements[sex][name] ? 'Tomb' : 'Project Zomboid';
}

export function rigAssetPath(name: string, sex: Sex, modelSet: ModelSet) {
  if (modelSet === 'tomb' && replacements[sex][name]) return replacements[sex][name].url;
  // Tomb replaces selected models, not the entire wardrobe. Unchanged models
  // retain their exact ClothingItem mapping and the same shared pose pipeline.
  return `/pz/rigs/${sex}/${name}.json`;
}

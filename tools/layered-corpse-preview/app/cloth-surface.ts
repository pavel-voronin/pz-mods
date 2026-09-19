import type * as THREE from 'three';
import type { ClothSurface } from './cloth-physics';

/** Physics only uses visible garment triangles, not invisible body-atlas regions. */
export function clothSurface(geometry: THREE.BufferGeometry, image: { data: Uint8ClampedArray; width: number; height: number }): ClothSurface {
  const position = geometry.getAttribute('position'), uv = geometry.getAttribute('uv');
  const sourceIndices = geometry.index?.array ?? Array.from({ length: position.count }, (_, i) => i);
  const indices: number[] = [];
  const opaque = (u: number, v: number) => {
    const x = Math.max(0, Math.min(image.width - 1, Math.floor(u * image.width)));
    const y = Math.max(0, Math.min(image.height - 1, Math.floor(v * image.height)));
    return image.data[(y * image.width + x) * 4 + 3] >= 3;
  };
  for (let i = 0; i < sourceIndices.length; i += 3) {
    const ids = [sourceIndices[i], sourceIndices[i + 1], sourceIndices[i + 2]];
    const samples = [[1 / 3, 1 / 3, 1 / 3], [0.8, 0.1, 0.1], [0.1, 0.8, 0.1], [0.1, 0.1, 0.8], [0.45, 0.45, 0.1], [0.1, 0.45, 0.45], [0.45, 0.1, 0.45]];
    if (samples.some((weights) => opaque(
      ids.reduce((sum, id, j) => sum + uv.getX(id) * weights[j], 0),
      ids.reduce((sum, id, j) => sum + uv.getY(id) * weights[j], 0),
    ))) indices.push(...ids);
  }
  const normal = geometry.getAttribute('normal');
  return { positions: new Float32Array(position.array), normals: normal ? new Float32Array(normal.array) : undefined,
    uvs: new Float32Array(uv.array), indices: new Uint32Array(indices) };
}

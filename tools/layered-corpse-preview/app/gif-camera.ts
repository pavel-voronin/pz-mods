import * as THREE from 'three';

export const GIF_FRAME_ASPECT = 16 / 9;
export function fitGifViewport(width: number, height: number) {
  const frameWidth = Math.max(1, Math.min(width, height * GIF_FRAME_ASPECT));
  return { width: frameWidth, height: frameWidth / GIF_FRAME_ASPECT };
}

/** Freeze the user's framing without lending the exporter the live camera. */
export function snapshotGifCamera(camera: THREE.OrthographicCamera, targetBytes: number) {
  const exportCamera = camera.clone();
  exportCamera.updateMatrixWorld(true);
  const aspect = (camera.right - camera.left) / (camera.top - camera.bottom);
  const longSide = 840 * THREE.MathUtils.clamp(Math.sqrt(targetBytes / 1_000_000), 0.7, 2);
  const even = (value: number) => Math.max(2, Math.round(value / 2) * 2);
  return {
    camera: exportCamera,
    width: even(aspect >= 1 ? longSide : longSide * aspect),
    height: even(aspect >= 1 ? longSide / aspect : longSide),
  };
}

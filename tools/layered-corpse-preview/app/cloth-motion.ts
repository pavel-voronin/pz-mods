import * as THREE from 'three';

type ClothMotion = {
  amount: number;
  seed: number;
  level: number;
  index: number;
  dressedPosition: THREE.Vector3;
  target: THREE.Vector3;
};

/** Apply an absolute sequencer frame, independent of the previous frame. */
export function applyClothMotion(group: THREE.Object3D, motion: ClothMotion) {
  const { amount, seed, level, index, dressedPosition, target } = motion;
  // While worn, the centering transforms must cancel exactly. This also
  // restores the original frame after scrubbing backward from detached cloth.
  group.position.copy(dressedPosition);
  group.quaternion.identity();
  group.scale.setScalar(1);
  if (amount <= 0) return 0;

  const ease = (value: number) => THREE.MathUtils.smoothstep(value, 0, 1);
  const lift = ease(amount / 0.22);
  const travel = ease((amount - 0.18) / 0.58);
  const settle = THREE.MathUtils.clamp((amount - 0.68) / 0.32, 0, 1);
  const landing = ease(settle);
  const tumble = Math.sin(travel * Math.PI) * (1 - landing);
  group.position.y += (0.19 + level * 0.012 + index * 0.003) * lift;
  group.position.lerp(target, travel);
  group.position.y += Math.sin(travel * Math.PI) * 0.12;
  group.rotation.set(
    tumble * (0.42 + Math.sin(seed) * 0.16),
    travel * (0.45 + (seed % 1) * 0.9),
    Math.sin(travel * Math.PI * 2 + seed) * 0.3 * tumble,
  );
  return settle;
}

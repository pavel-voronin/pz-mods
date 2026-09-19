export type SequenceActionKind = 'hold' | 'axe' | 'layer' | 'final';

export type SequenceAction = {
  id: string;
  kind: SequenceActionKind;
  label: string;
  layer?: number;
  start: number;
  end: number;
};

export type SequenceKeyframe = {
  rotation: number;
};

type WeightedAction = Omit<SequenceAction, 'start' | 'end'> & { weight: number };

export function buildSequence(levels: number[]): SequenceAction[] {
  const uniqueLevels = [...new Set(levels)].sort((a, b) => b - a);
  const weighted: WeightedAction[] = [
    { id: 'dressed', kind: 'hold', label: 'Одетый зомби', weight: 0.45 },
    { id: 'axe', kind: 'axe', label: 'Топор', weight: 0.65 },
    ...uniqueLevels.map((layer) => ({
      id: `layer-${layer}`,
      kind: 'layer' as const,
      label: `Слой ${layer + 1}`,
      layer,
      weight: 1.1,
    })),
    { id: 'naked', kind: 'final', label: 'Готово', weight: 1.4 },
  ];
  const total = weighted.reduce((sum, action) => sum + action.weight, 0);
  let cursor = 0;
  return weighted.map(({ weight, ...action }) => {
    const start = cursor / total;
    cursor += weight;
    return { ...action, start, end: cursor / total };
  });
}

export function actionAt(actions: SequenceAction[], progress: number) {
  const clamped = Math.max(0, Math.min(1, progress));
  return actions.find((action) => clamped >= action.start && clamped < action.end)
    ?? actions.at(-1)!;
}

export function actionProgress(action: SequenceAction, progress: number) {
  return Math.max(0, Math.min(1, (progress - action.start) / Math.max(1e-6, action.end - action.start)));
}

export function smoothstep(value: number) {
  const clamped = Math.max(0, Math.min(1, value));
  return clamped * clamped * (3 - 2 * clamped);
}

export function defaultSequenceKeyframe(action: SequenceAction, index: number): SequenceKeyframe {
  void action;
  void index;
  return { rotation: 0 };
}

export function shortestAngle(from: number, to: number) {
  let delta = (to - from) % (Math.PI * 2);
  if (delta > Math.PI) delta -= Math.PI * 2;
  if (delta < -Math.PI) delta += Math.PI * 2;
  return from + delta;
}

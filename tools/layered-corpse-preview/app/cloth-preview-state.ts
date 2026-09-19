export type ClothPreviewState = 'quick' | 'stale' | 'calculating' | 'ready' | 'cached' | 'error';

export const invalidateClothPreview = (state: ClothPreviewState): ClothPreviewState => state === 'quick' ? 'quick' : 'stale';
export const clothPreviewLabels: Record<ClothPreviewState, string> = {
  quick: 'Быстрая ткань · точный расчёт не выполнен',
  stale: 'Быстрая ткань · точный расчёт устарел',
  calculating: 'Точный расчёт ткани',
  ready: 'Точный расчёт ткани готов',
  cached: 'Быстрая ткань · точный расчёт сохранён',
  error: 'Быстрая ткань · ошибка точного расчёта',
};
export const clothPreviewActions: Record<ClothPreviewState, string> = {
  quick: 'Рассчитать ткань', stale: 'Пересчитать ткань', calculating: 'Отменить расчёт',
  ready: 'Быстрая ткань', cached: 'Показать точный расчёт', error: 'Повторить расчёт',
};

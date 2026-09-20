export const OWNER = '76561198008387517';
export const APP_ID = 108600;
export const PROFILE = 'https://steamcommunity.com/id/huzeru/myworkshopfiles/?appid=108600&numperpage=30';
export const dayKey = date => new Date(date).toISOString().slice(0, 10);
export function shiftDay(day, amount) {
  const date = new Date(`${day}T12:00:00Z`);
  date.setUTCDate(date.getUTCDate() + amount);
  return dayKey(date);
}
export function windowSum(series, end, days) {
  const start = shiftDay(end, 1 - days);
  return series.reduce((sum, [date, value]) => sum + (date >= start && date <= end ? value : 0), 0);
}
export function parseTotals(table) {
  const section = (heading, next) => table.split(heading)[1]?.split(next)[0] || '';
  const number = (text, pattern) => {
    const match = text.match(pattern);
    if (!match) throw new Error('Не удалось прочитать счётчики Steam.');
    return Number(match[1].replaceAll(',', ''));
  };
  return {
    subscriptions: number(section('SUBSCRIBERS', 'FAVORITES'), /Current\s+([\d,]+)/),
    favorited: number(section('FAVORITES', 'RATINGS'), /Current\s+([\d,]+)/),
    votesUp: number(table, /Positive ratings\s+([\d,]+)/),
    votesDown: number(table, /Negative ratings\s+([\d,]+)/),
    views: number(section('VISITORS', 'SUBSCRIBERS'), /Total Unique[^\d]*([\d,]+)/),
  };
}
export function normalizeHistory(raw, capturedAt = new Date().toISOString()) {
  if (!raw || !/^\d{8,20}$/.test(raw.id) || !Array.isArray(raw.daily) || raw.daily.length !== 5 || typeof raw.table !== 'string') {
    throw new Error('В файле нет ожидаемой статистики Workshop.');
  }
  const daily = raw.daily.map((series, index) => {
    if (!Array.isArray(series) || series.length > 20000) throw new Error('Некорректный ряд статистики.');
    const seen = new Set();
    return series.map(point => {
      // Steam can report negative rating corrections when votes are changed or removed.
      if (!Array.isArray(point) || point.length !== 2 || !/^\d{4}-\d{2}-\d{2}$/.test(point[0]) || !Number.isSafeInteger(point[1]) || (point[1] < 0 && index > 2) || seen.has(point[0])) {
        throw new Error('Некорректная дата или значение в статистике.');
      }
      seen.add(point[0]);
      return point;
    }).sort((a,b) => a[0].localeCompare(b[0]));
  });
  return {id: raw.id, daily, totals: parseTotals(raw.table), capturedAt};
}
export function historySummary(history) {
  if (!history) return null;
  // Steam exposes calendar dates, not hourly observations. Exclude the partial capture day.
  const end = shiftDay(dayKey(history.capturedAt), -1);
  return {
    capturedAt: history.capturedAt, end,
    subscriptions: [1, 7, 30].map(days => windowSum(history.daily[4], end, days)),
    views: [1, 7, 30].map(days => windowSum(history.daily[3], end, days)),
    votes: [1, 7, 30].map(days => windowSum(history.daily[0], end, days)),
    todaySubscriptions: windowSum(history.daily[4], shiftDay(end, 1), 1),
    timeline: Array.from({length:30}, (_,i) => {
      const day = shiftDay(end, i-29);
      return [day, windowSum(history.daily[4], day, 1)];
    }),
    votesUp: history.totals.votesUp, votesDown: history.totals.votesDown,
  };
}

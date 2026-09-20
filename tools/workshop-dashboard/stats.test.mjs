import test from 'node:test';
import assert from 'node:assert/strict';
import {normalizeHistory, historySummary, shiftDay, windowSum} from './stats.mjs';
const totals='VISITORS\nTotal Unique (?)\t2,146\nSUBSCRIBERS\nCurrent\t171\nTotal Unique (?)\t592\nFAVORITES\nCurrent\t32\nTotal Unique (?)\t42\nRATINGS\nTotal ratings\t10\nPositive ratings\t10 (100% of total)\nNegative ratings\t0 (0% of total)';
test('Calendar windows include their boundaries and exclude the incomplete capture day',()=>{
  const history=normalizeHistory({id:'3531779349',table:totals,daily:[[],[],[],[],[['2026-08-20',100],['2026-08-21',4],['2026-09-12',3],['2026-09-13',2],['2026-09-19',1],['2026-09-20',100]]]},'2026-09-20T12:00:00Z');
  const result=historySummary(history);
  assert.deepEqual(result.subscriptions,[1,3,10]);
  assert.equal(result.todaySubscriptions,100);
  assert.equal(result.timeline.length,30);
  assert.equal(result.timeline[0][0],'2026-08-21');
  assert.equal(result.timeline.at(-1)[0],'2026-09-19');
  assert.equal(history.totals.views,2146);
  assert.equal(history.totals.subscriptions,171);
});
test('A successful sparse series means zero actions on absent days',()=>{
  assert.equal(windowSum([['2026-09-17',2]],'2026-09-19',1),0);
  assert.equal(historySummary(null),null);
});
test('Dates cross leap days and year boundaries without local timezone arithmetic',()=>{
  assert.equal(shiftDay('2024-03-01',-1),'2024-02-29');
  assert.equal(shiftDay('2026-01-01',-1),'2025-12-31');
});
test('Keep real negative rating corrections returned by Steam',()=>{
  const history=normalizeHistory({id:'3493062213',table:totals,daily:[[],[['2025-08-18',-1]],[],[],[]]});
  assert.equal(history.daily[1][0][1],-1);
});
test('Reject malformed or duplicate history instead of presenting false zeroes',()=>{
  assert.throws(()=>normalizeHistory({id:'3531779349',table:totals,daily:null}));
  assert.throws(()=>normalizeHistory({id:'3531779349',table:totals,daily:[[],[],[],[],[['2026-09-01',-1]]]}));
  assert.throws(()=>normalizeHistory({id:'3531779349',table:totals,daily:[[],[],[],[],[['2026-09-01',1],['2026-09-01',2]]]}));
});

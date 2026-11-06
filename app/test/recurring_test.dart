import 'package:cukup/core/recurring.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rent on the 1st posts once the day arrives, then not again', () {
    expect(dueMonths(today: '2026-11-01', day: 1, lastPosted: '2026-10'), ['2026-11']);
    expect(dueMonths(today: '2026-11-04', day: 1, lastPosted: '2026-11'), isEmpty);
  });

  test('app closed for 3 days over the 1st still posts exactly one entry', () {
    // Last opened 29 Oct (October already posted), opened again on 3 Nov.
    expect(dueMonths(today: '2026-11-03', day: 1, lastPosted: '2026-10'), ['2026-11']);
  });

  test('a day that has not arrived yet posts nothing', () {
    expect(dueMonths(today: '2026-11-10', day: 15, lastPosted: '2026-10'), isEmpty);
  });

  test('missed months are all caught up, oldest first, across a year end', () {
    expect(dueMonths(today: '2027-02-03', day: 1, lastPosted: '2026-11'), ['2026-12', '2027-01', '2027-02']);
  });

  test('a brand-new item with no history posts only the current month when due', () {
    expect(dueMonths(today: '2026-11-05', day: 1, lastPosted: null), ['2026-11']);
    expect(dueMonths(today: '2026-11-05', day: 20, lastPosted: null), isEmpty);
  });

  test('catch-up is capped at the last 12 months', () {
    expect(dueMonths(today: '2026-11-05', day: 1, lastPosted: '2020-01').length, 12);
  });

  test('shiftMonth wraps years', () {
    expect(shiftMonth('2026-01', -1), '2025-12');
    expect(shiftMonth('2026-12', 1), '2027-01');
  });
}

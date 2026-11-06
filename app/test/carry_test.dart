import 'package:cukup/core/carry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  int next(List<int> past, {int base = 25000}) => carryOver(base: base, pastSpent: past).effective;

  test('no history means the full cap', () => expect(next([]), 25000));
  test('under the cap last week changes nothing', () => expect(next([20000]), 25000));
  test('RM 40 over comes off next week', () => expect(next([29000]), 21000));
  test('underspending never adds to the next week', () => expect(next([0, 0, 0]), 25000));
  test('debt is paid back after one week', () => expect(next([29000, 15000]), 25000));
  test('a huge overspend takes at most half of the cap per week', () => expect(next([50000]), 12500)); // RM 250 over, only RM 125 comes off
  test('the rest rolls on to the following week', () {
    // week 1: 500 spent, debt 250. week 2: cut 125 (cap 125), spent 100, debt 125. week 3: cut 125.
    expect(next([50000, 10000]), 12500);
    // week 3 spent 100 as well: debt 0, week 4 is back to the full cap.
    expect(next([50000, 10000, 10000]), 25000);
  });
  test('overspending a reduced cap carries again', () {
    // week 1: 290 (debt 40). week 2 cap 210, spent 260: over by 50, debt = 40 - 40 + 50 = 50.
    expect(next([29000, 26000]), 20000);
  });
  test('spending exactly the cap is not overspending', () => expect(next([25000]), 25000));
  test('carried amount is the cut', () => expect(carryOver(base: 25000, pastSpent: [29000]).carried, 4000));
  test('a zero cap stays zero', () => expect(next([100], base: 0), 0));
}

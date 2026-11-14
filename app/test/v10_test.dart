import 'package:cukup/core/app_state.dart';
import 'package:cukup/core/month_review.dart';
import 'package:cukup/core/txn_filter.dart';
import 'package:cukup/data/db.dart';
import 'package:flutter_test/flutter_test.dart';

var _n = 0;
Txn t(String date, int cents, {String shop = 'Shop', int cat = 1, String direction = 'spend', String pay = 'ewallet', bool cap = true, String? note, bool deleted = false}) => Txn(
      id: 'id${_n++}',
      spentAt: date,
      merchant: shop,
      amountCents: cents,
      taxCents: 0,
      direction: direction,
      categoryId: cat,
      paymentType: pay,
      countsTowardCap: cap,
      note: note,
      source: 'manual',
      createdAt: '2026-11-01T00:00:00.000Z',
      updatedAt: '2026-11-01T00:00:00.000Z',
      deletedAt: deleted ? '2026-11-02T00:00:00.000Z' : null,
    );

void main() {
  group('Activity filters', () {
    const today = '2026-11-14'; // a Saturday; the week is 9 to 15 Nov
    final all = [
      t('2026-11-14', 1000, shop: 'Mixue'),
      t('2026-11-10', 2800, shop: 'Weng Hoe Auto', cat: 3, pay: 'credit_card'),
      t('2026-11-03', 9000, shop: 'TNB', cat: 4, cap: false, note: 'electricity'),
      t('2026-10-20', 500, shop: 'Kopitiam'),
      t('2026-11-05', 150000, shop: 'Allowance', cat: 8, direction: 'income'),
    ];
    const names = {1: 'Food', 3: 'Transport', 4: 'Bills', 8: 'Allowance'};
    List<String> shops(TxnFilter f) => applyFilter(all, f, today: today, categoryNames: names).map((x) => x.merchant).toList();

    test('no filter shows everything', () {
      expect(shops(const TxnFilter()).length, 5);
      expect(const TxnFilter().isActive, isFalse);
    });

    test('periods run Monday to Sunday and by calendar month', () {
      expect(shops(const TxnFilter(period: 'week')), ['Mixue', 'Weng Hoe Auto']);
      expect(shops(const TxnFilter(period: 'month')), ['Mixue', 'Weng Hoe Auto', 'TNB', 'Allowance']);
      expect(shops(const TxnFilter(period: 'last_month')), ['Kopitiam']);
      expect(shops(const TxnFilter(period: 'custom', from: '2026-11-03', to: '2026-11-05')), ['TNB', 'Allowance']);
      expect(periodRange(const TxnFilter(period: 'month'), today), (from: '2026-11-01', to: '2026-11-30'));
      expect(periodRange(const TxnFilter(period: 'last_month'), '2026-01-15'), (from: '2025-12-01', to: '2025-12-31'));
    });

    test('paid with and outside-the-cap only look at spending', () {
      expect(shops(const TxnFilter(paymentType: 'credit_card')), ['Weng Hoe Auto']);
      expect(shops(const TxnFilter(outsideCap: true)), ['TNB']);
      expect(shops(const TxnFilter(paymentType: 'ewallet')).contains('Allowance'), isFalse);
    });

    test('search matches shop, note and category, and filters combine', () {
      expect(shops(const TxnFilter(query: 'ELECTR')), ['TNB']);
      expect(shops(const TxnFilter(query: 'transport')), ['Weng Hoe Auto']);
      expect(shops(const TxnFilter(query: 'mixue', period: 'last_month')), isEmpty);
      expect(shops(const TxnFilter(direction: 'income')), ['Allowance']);
      expect(shops(const TxnFilter(categoryId: 1, period: 'month')), ['Mixue']);
    });

    test('totals and copyWith', () {
      final shown = applyFilter(all, const TxnFilter(period: 'month'), today: today);
      expect(totalsOf(shown), (count: 4, spentCents: 12800, incomeCents: 150000));
      const f = TxnFilter(categoryId: 3, paymentType: 'cash');
      expect(f.copyWith(categoryId: () => null).categoryId, isNull);
      expect(f.copyWith(direction: 'spend').categoryId, 3); // left alone unless asked
      expect(f.hasExtra, isTrue);
    });
  });

  group('Month in review', () {
    final txns = [
      t('2026-11-02', 20000, cat: 1), // week of 2 Nov
      t('2026-11-04', 9000, cat: 4, cap: false, shop: 'TNB'),
      t('2026-11-10', 30000, cat: 3, shop: 'Tyres'), // week of 9 Nov: over a 250 cap
      t('2026-11-11', 1000, cat: 1),
      t('2026-11-05', 150000, cat: 8, direction: 'income'),
      t('2026-10-15', 40000, cat: 1),
      t('2026-11-12', 99999, deleted: true),
    ];

    test('adds up the month and compares with the one before', () {
      final r = reviewMonth(txns, '2026-11', capCents: 25000, today: '2026-11-30', sweeps: {'2026-11-02': 5000, '2026-10-19': 700});
      expect(r.spentCents, 60000);
      expect(r.incomeCents, 150000);
      expect(r.keptCents, 90000);
      expect(r.prevSpentCents, 40000);
      expect(r.changeCents, 20000);
      expect(r.outsideCapCents, 9000);
      expect(r.entries, 5); // the deleted one is not counted
      expect(r.topCategories.first, (categoryId: 3, cents: 30000));
      expect(r.biggest!.merchant, 'Tyres');
      expect(r.sweptCents, 5000); // only weeks that ended in November
    });

    test('counts only finished weeks that ended in the month', () {
      // Sundays in Nov 2026: 1, 8, 15, 22, 29. On the 30th all five are over.
      final r = reviewMonth(txns, '2026-11', capCents: 25000, today: '2026-11-30');
      expect(r.weeksCounted, 5);
      expect(r.weeksUnderCap, 4); // the week of 9 Nov went over; the bill outside the cap did not count
      final mid = reviewMonth(txns, '2026-11', capCents: 25000, today: '2026-11-14');
      expect(mid.weeksCounted, 2); // weeks ending 1 and 8 Nov
    });

    test('month helpers', () {
      expect(shiftMonth('2026-01', -1), '2025-12');
      expect(shiftMonth('2026-12', 1), '2027-01');
      expect(monthName('2026-11'), 'November 2026');
      expect(reviewMonth(const [], '2026-11', capCents: 0, today: '2026-11-30').changeCents, isNull);
    });
  });

  group('App state sync', () {
    test('only known settings travel', () {
      expect(isSynced('goal.name'), isTrue);
      expect(isSynced('rule.mixue kajang'), isTrue);
      expect(isSynced('sweep.2026-11-02'), isTrue);
      expect(isSynced('setting.weekly_cap_cents'), isFalse); // the server owns this one
      expect(isSynced('meta.pull_cursor'), isFalse);
      expect(decodeState('{"v":1,"kv":{"goal.name":"Laptop","meta.x":"1","rule.kfc":3}}'), {'goal.name': 'Laptop'});
      expect(decodeState('not json'), isEmpty);
    });

    test('the document is stable and round-trips', () {
      final a = encodeState({'rule.b': '2', 'goal.name': 'Trip'});
      expect(a, encodeState({'goal.name': 'Trip', 'rule.b': '2'}));
      expect(decodeState(a), {'goal.name': 'Trip', 'rule.b': '2'});
    });

    test('a fresh install takes what the server has', () {
      expect(mergeState(local: {}, synced: null, remote: {'goal.name': 'Trip', 'rule.kfc': '1'}), {'goal.name': 'Trip', 'rule.kfc': '1'});
    });

    test('nothing changed here: the server copy wins', () {
      final synced = {'goal.name': 'Trip'};
      expect(mergeState(local: {...synced}, synced: synced, remote: {'goal.name': 'Laptop', 'rule.kfc': '1'}), {'goal.name': 'Laptop', 'rule.kfc': '1'});
    });

    test('changed here: both are kept and the phone wins where they differ', () {
      final merged = mergeState(local: {'goal.name': 'Bike', 'rule.mixue': '1'}, synced: {'goal.name': 'Trip'}, remote: {'goal.name': 'Laptop', 'rule.kfc': '1'});
      expect(merged, {'goal.name': 'Bike', 'rule.mixue': '1', 'rule.kfc': '1'});
    });

    test('nothing on the server yet: the phone copy goes up', () {
      expect(mergeState(local: {'goal.name': 'Trip'}, synced: null, remote: null), {'goal.name': 'Trip'});
      expect(sameState({'a': '1'}, {'a': '1'}), isTrue);
      expect(sameState({'a': '1'}, {'a': '2'}), isFalse);
    });
  });
}

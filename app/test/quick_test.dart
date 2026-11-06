import 'package:cukup/core/quick.dart';
import 'package:cukup/data/db.dart';
import 'package:flutter_test/flutter_test.dart';

Txn _t(String merchant, int cents, {String direction = 'spend', String source = 'manual', int cat = 1, String pay = 'ewallet'}) => Txn(
      id: '$merchant$cents${DateTime.now().microsecondsSinceEpoch}',
      spentAt: '2026-11-03',
      merchant: merchant,
      amountCents: cents,
      taxCents: 0,
      direction: direction,
      categoryId: cat,
      paymentType: pay,
      countsTowardCap: true,
      source: source,
      createdAt: '2026-11-03T01:00:00.000Z',
      updatedAt: '2026-11-03T01:00:00.000Z',
    );

void main() {
  group('topMerchants', () {
    test('ranks by use and keeps the latest amount', () {
      // newest first
      final r = topMerchants([_t('Kopi', 650), _t('Grab', 1200), _t('kopi', 600), _t('KOPI', 550), _t('Grab', 900)]);
      expect(r.map((m) => m.name), ['Kopi', 'Grab']);
      expect(r.first.count, 3);
      expect(r.first.lastAmountCents, 650);
    });

    test('ignores income and recurring entries, caps at six', () {
      final r = topMerchants([
        _t('Salary', 500000, direction: 'income'),
        _t('Rent', 80000, source: 'recurring'),
        for (var i = 0; i < 8; i++) _t('Shop$i', 100 + i),
      ]);
      expect(r.length, 6);
      expect(r.any((m) => m.name == 'Salary' || m.name == 'Rent'), isFalse);
    });

    test('ties go to the more recent shop', () {
      final r = topMerchants([_t('A', 100), _t('B', 200)]);
      expect(r.map((m) => m.name), ['A', 'B']);
    });
  });

  group('applyKey', () {
    String type(List<String> keys) => keys.fold('', applyKey);

    test('builds amounts', () => expect(type(['1', '2', '.', '5']), '12.5'));
    test('limits to two decimals', () => expect(type(['1', '.', '2', '3', '4']), '1.23'));
    test('a leading dot becomes 0.', () => expect(type(['.', '5']), '0.5'));
    test('no leading zeros', () => expect(type(['0', '0', '7']), '7'));
    test('only one dot', () => expect(type(['1', '.', '.', '2']), '1.2'));
    test('back removes the last key', () => expect(type(['1', '2', 'back']), '1'));
    test('back on empty stays empty', () => expect(type(['back']), ''));
    test('caps whole digits', () => expect(type(List.filled(10, '9')).length, 7));
  });
}

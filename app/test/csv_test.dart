import 'package:cukup/core/csv.dart';
import 'package:cukup/data/db.dart';
import 'package:flutter_test/flutter_test.dart';

Txn _t({String merchant = 'Kopitiam', int cents = 1250, String? note, String direction = 'spend'}) => Txn(
      id: 'a1',
      spentAt: '2026-11-03',
      merchant: merchant,
      amountCents: cents,
      taxCents: 0,
      direction: direction,
      categoryId: 1,
      paymentType: 'cash',
      countsTowardCap: true,
      note: note,
      source: 'manual',
      createdAt: '2026-11-03T01:00:00.000Z',
      updatedAt: '2026-11-03T01:00:00.000Z',
    );

void main() {
  test('writes a header and one row per entry', () {
    final csv = buildCsv([_t()], {1: 'Food'});
    final lines = csv.trim().split('\r\n');
    expect(lines.first, 'date,merchant,type,category,amount_rm,payment,counts_toward_cap,note,source');
    expect(lines[1], '2026-11-03,Kopitiam,spend,Food,12.50,cash,yes,,manual');
  });

  test('quotes commas and quotes, and defuses formulas', () {
    final csv = buildCsv([_t(merchant: 'Ah, Seng "Café"', note: '=HYPERLINK("x")')], {1: 'Food'});
    expect(csv, contains('"Ah, Seng ""Café"""'));
    expect(csv, contains('"\'=HYPERLINK(""x"")"'));
  });

  test('amounts keep two decimals', () {
    expect(buildCsv([_t(cents: 5)], {}).contains(',0.05,'), isTrue);
    expect(buildCsv([_t(cents: 100000)], {}).contains(',1000.00,'), isTrue);
  });
}

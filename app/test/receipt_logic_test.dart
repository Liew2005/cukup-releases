import 'package:cukup/core/split.dart';
import 'package:cukup/data/local_parser.dart';
import 'package:flutter_test/flutter_test.dart';

({int priceCents, bool included}) it(int p, bool inc) => (priceCents: p, included: inc);

void main() {
  group('yourShare', () {
    test('all ticked gives exactly the receipt total', () {
      expect(yourShare(totalCents: 2150, items: [it(980, true), it(250, true), it(800, true)]), 2150);
    });
    test('splits tax and rounding in proportion', () {
      // items 20.30, total 21.50. Keep 9.80 of 20.30 -> 21.50 * 980 / 2030 = 10.38
      expect(yourShare(totalCents: 2150, items: [it(980, true), it(250, false), it(800, false)]), 1038);
    });
    test('nothing ticked is zero', () {
      expect(yourShare(totalCents: 2150, items: [it(980, false), it(1050, false)]), 0);
    });
    test('no items falls back to the total', () {
      expect(yourShare(totalCents: 1234, items: []), 1234);
    });
    test('never exceeds the total, even with discount lines', () {
      final s = yourShare(totalCents: 800, items: [it(1000, true), it(-200, false)]);
      expect(s, lessThanOrEqualTo(800));
      expect(s, greaterThanOrEqualTo(0));
    });
  });

  group('LocalReceiptParser', () {
    const today = '2026-11-04';

    test('reads a typical Malaysian kopitiam receipt', () {
      final r = LocalReceiptParser.parse('''
KOPITIAM LIM KEE SDN BHD
Jln Reko, Kajang
Tel: 03-8736 1234
Date: 03/11/2026 12:41
Nasi lemak ayam 9.80
Teh ais 2.50
Mee goreng 8.00
Subtotal 20.30
SST 6% 1.22
Rounding -0.02
TOTAL RM 21.50
CASH 50.00
CHANGE 28.50
''', today: today);
      expect(r.merchant, 'KOPITIAM LIM KEE SDN BHD');
      expect(r.date, '2026-11-03');
      expect(r.items.map((i) => i.name), ['Nasi lemak ayam', 'Teh ais', 'Mee goreng']);
      expect(r.items.map((i) => i.priceCents), [980, 250, 800]);
      expect(r.taxCents, 122);
      expect(r.roundingCents, -2);
      expect(r.totalCents, 2150);
      expect(r.warnings, isEmpty);
      expect(r.via, 'offline');
    });

    test('flags items that do not add up', () {
      final r = LocalReceiptParser.parse('SHOP A\nItem one 10.00\nTOTAL 25.00', today: today);
      expect(r.warnings.any((w) => w.startsWith('total_mismatch_')), isTrue);
      expect(r.confidence, lessThan(0.5));
    });

    test('infers a missing total', () {
      final r = LocalReceiptParser.parse('SHOP A\nItem one 10.00\nItem two 5.00', today: today);
      expect(r.totalCents, 1500);
      expect(r.warnings, contains('total_inferred'));
    });

    test('prices that already include tax are accepted', () {
      final r = LocalReceiptParser.parse('SHOP A\nItem one 10.00\nItem two 5.00\nSST 6% 0.85\nTOTAL 15.00', today: today);
      expect(r.warnings, contains('prices_include_tax'));
    });

    test('handles other date styles and rejects bad ones', () {
      expect(LocalReceiptParser.parse('X SHOP\nA 1.00\n2026-10-30 10:00', today: today).date, '2026-10-30');
      expect(LocalReceiptParser.parse('X SHOP\nA 1.00\n03 Nov 2026', today: today).date, '2026-11-03');
      expect(LocalReceiptParser.parse('X SHOP\nA 1.00\n31/02/2026', today: today).date, isNull);
      expect(LocalReceiptParser.parse('X SHOP\nA 1.00\n01/01/2030', today: today).date, isNull);
    });

    test('quantity columns are trimmed off item names', () {
      final r = LocalReceiptParser.parse('SHOP A\nTeh ais 2 2.50 5.00\nTOTAL 5.00', today: today);
      expect(r.items.single.name, 'Teh ais');
      expect(r.items.single.priceCents, 500);
    });

    test('empty or junk text does not throw', () {
      expect(() => LocalReceiptParser.parse('', today: today), returnsNormally);
      expect(LocalReceiptParser.parse('asdf qwer', today: today).warnings, contains('no_items'));
    });
  });
}

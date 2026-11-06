import 'package:cukup/core/guards.dart';
import 'package:cukup/core/import_parser.dart';
import 'package:cukup/data/db.dart';
import 'package:flutter_test/flutter_test.dart';

Txn _t(String id, String merchant, int cents, String date, {String? ref, String? deleted, String direction = 'spend'}) => Txn(
      id: id,
      spentAt: date,
      merchant: merchant,
      amountCents: cents,
      taxCents: 0,
      direction: direction,
      categoryId: 1,
      paymentType: 'ewallet',
      countsTowardCap: true,
      source: 'manual',
      reference: ref,
      deletedAt: deleted,
      createdAt: '2026-11-03T01:00:00.000Z',
      updatedAt: '2026-11-03T01:00:00.000Z',
    );

void main() {
  const today = '2026-11-05';

  group('parseImport', () {
    test('Touch n Go style payment', () {
      final r = parseImport('Payment Successful\nRM 12.50\nPaid to Kopitiam Ah Seng\nDate 3 Nov 2026 14:22\nReference No 20261103ABC123', today: today)!;
      expect(r.amountCents, 1250);
      expect(r.payee, 'Kopitiam Ah Seng');
      expect(r.reference, '20261103ABC123');
      expect(r.date, '2026-11-03');
    });

    test('bank transfer with labels and values on separate rows', () {
      final r = parseImport('Transfer Successful\nAmount\nRM 1,250.00\nTo\nAHMAD BIN ALI\nReference ID\nMBB77881234\n03/11/2026', today: today)!;
      expect(r.amountCents, 125000);
      expect(r.payee, 'AHMAD BIN ALI');
      expect(r.reference, 'MBB77881234');
      expect(r.date, '2026-11-03');
    });

    test('prefers the labelled amount over a fee line', () {
      final r = parseImport('Service fee RM 0.50\nTotal Amount RM 30.00\nMerchant: Grab', today: today)!;
      expect(r.amountCents, 3000);
      expect(r.payee, 'Grab');
    });

    test('a bare amount still imports, with nothing else', () {
      final r = parseImport('RM8.90', today: today)!;
      expect(r.amountCents, 890);
      expect(r.payee, isNull);
      expect(r.reference, isNull);
    });

    test('no amount means no import', () => expect(parseImport('Hello there\nNo money here', today: today), isNull));
    test('future dates are ignored', () => expect(parseImport('RM5.00\n01 Dec 2026', today: today)!.date, isNull));
  });

  group('findDuplicate', () {
    final list = [_t('a', 'Kopi Corner', 650, '2026-11-04', ref: 'R123456')];

    test('same shop, amount, next day', () => expect(findDuplicate(list, merchant: 'kopi  corner', amountCents: 650, date: '2026-11-05')?.id, 'a'));
    test('two days apart is fine', () => expect(findDuplicate(list, merchant: 'Kopi Corner', amountCents: 650, date: '2026-11-06'), isNull));
    test('different amount is fine', () => expect(findDuplicate(list, merchant: 'Kopi Corner', amountCents: 700, date: '2026-11-04'), isNull));
    test('same reference matches whatever the shop', () => expect(findDuplicate(list, merchant: 'Other', amountCents: 1, date: '2026-01-01', reference: 'R123456')?.id, 'a'));
    test('deleted entries do not count', () => expect(findDuplicate([_t('b', 'Kopi Corner', 650, '2026-11-04', deleted: '2026-11-04T01:00:00Z')], merchant: 'Kopi Corner', amountCents: 650, date: '2026-11-04'), isNull));
    test('editing an entry never matches itself', () => expect(findDuplicate(list, merchant: 'Kopi Corner', amountCents: 650, date: '2026-11-04', ignoreId: 'a'), isNull));
    test('income does not match spending', () => expect(findDuplicate([_t('c', 'Kopi Corner', 650, '2026-11-04', direction: 'income')], merchant: 'Kopi Corner', amountCents: 650, date: '2026-11-04'), isNull));
  });

  group('sweep', () {
    test('under the cap', () => expect(sweepable(capCents: 25000, spentCents: 18000), 7000));
    test('over the cap shows nothing', () => expect(sweepable(capCents: 25000, spentCents: 26000), isNull));
    test('exactly on the cap shows nothing', () => expect(sweepable(capCents: 25000, spentCents: 25000), isNull));
    test('goal progress is capped at 1', () {
      expect(goalProgress(savedCents: 5000, targetCents: 20000), 0.25);
      expect(goalProgress(savedCents: 30000, targetCents: 20000), 1);
      expect(goalProgress(savedCents: 100, targetCents: 0), 0);
    });
  });
}

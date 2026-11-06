import 'package:cukup/data/local_parser.dart';
import 'package:cukup/data/receipt_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('quantity, unit price and line total are kept together; no tax is invented', () {
    const text = '''
Chicken Rice
Y & X Food Enterprise
INVOICE
Date : 06/11/2026 12:49:53
ITEM QTY U/P(RM) DISC(%) Amt
烧鸡+叉烧/烧肉饭 004 3 11.00 0.00 33.00
LS 凉水 D2 2 2.20 0.00 4.40
烧鸡饭SG 001 1 8.50 0.00 8.50
Sub Total Before Disco RM 45.90
Service Charge RM 0.00
TOTAL RM 45.90
''';
    final r = LocalReceiptParser.parse(text, today: '2026-11-06');
    expect(r.items.length, 3);
    expect(r.items[0].qty, 3);
    expect(r.items[0].unitCents, 1100);
    expect(r.items[0].priceCents, 3300);
    expect(r.items[1].qty, 2);
    expect(r.items[1].unitCents, 220);
    expect(r.items[2].qty, 1);
    expect(r.taxCents, 0);
    expect(r.serviceCents, 0);
    expect(r.sstCents, 0);
    expect(r.totalCents, 4590);
    expect(r.date, '2026-11-06');
  });

  test('printed service charge and SST are read separately', () {
    const text = '''
Cafe Lim
Nasi lemak 10.00
Teh ais 4.00
Sub Total 14.00
Service Charge 10% 1.40
SST 6% 0.92
Rounding 0.03
TOTAL 16.35
''';
    final r = LocalReceiptParser.parse(text, today: '2026-11-06');
    expect(r.serviceCents, 140);
    expect(r.sstCents, 92);
    expect(r.taxCents, 232);
    expect(r.roundingCents, 3);
    expect(r.totalCents, 1635);
  });

  test('server reply with qty and separate charges', () {
    final r = ParsedReceipt.fromServer({
      'items': [
        {'name': 'Rice', 'price_cents': 3300, 'qty': 3, 'unit_cents': 1100},
        {'name': 'Tea', 'price_cents': 440},
      ],
      'tax_cents': 232,
      'service_cents': 140,
      'sst_cents': 92,
      'total_cents': 3972,
      'confidence': 0.9,
    });
    expect(r.items[0].qty, 3);
    expect(r.items[0].unitCents, 1100);
    expect(r.items[1].qty, 1);
    expect(r.items[1].unitCents, 440);
    expect(r.serviceCents, 140);
    expect(r.sstCents, 92);
  });
}

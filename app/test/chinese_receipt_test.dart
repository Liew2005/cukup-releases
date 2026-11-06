import 'package:cukup/data/local_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const today = '2026-11-04';

  test('reads a Chinese-language kopitiam receipt', () {
    final r = LocalReceiptParser.parse('''
美味茶餐室
日期: 2026年11月3日
鸡饭 8.50
冰茶 2.50
小计 11.00
服务税 0.66
四舍五入 -0.01
总计 RM 11.65
现金 20.00
找零 8.35
''', today: today);
    expect(r.merchant, '美味茶餐室');
    expect(r.date, '2026-11-03');
    expect(r.items.map((i) => i.name), ['鸡饭', '冰茶']);
    expect(r.items.map((i) => i.priceCents), [850, 250]);
    expect(r.taxCents, 66);
    expect(r.roundingCents, -1);
    expect(r.totalCents, 1165);
    expect(r.warnings, isEmpty);
  });

  test('mixed English and Chinese item names', () {
    final r = LocalReceiptParser.parse('KEDAI MAKAN ABC\nNasi lemak 椰浆饭 6.00\nTotal 6.00', today: today);
    expect(r.items.single.name, 'Nasi lemak 椰浆饭');
    expect(r.totalCents, 600);
  });

  test('shop names containing tel, reg or lot are not skipped', () {
    expect(LocalReceiptParser.parse('HOTEL REGAL CAFE\nTea 5.00\nTotal 5.00', today: today).merchant, 'HOTEL REGAL CAFE');
    expect(LocalReceiptParser.parse('Tel: 03-1234 5678\nLOTUS BAKERY\nBun 3.00\nTotal 3.00', today: today).merchant, 'LOTUS BAKERY');
  });
}

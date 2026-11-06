import 'package:cukup/core/ledger.dart';
import 'package:cukup/core/split_bill.dart';
import 'package:flutter_test/flutter_test.dart';

int sum(Map<String, int> m) => m.values.fold(0, (a, b) => a + b);

void main() {
  test('no friends: everything ticked is yours, total unchanged', () {
    final r = splitTotals([const Slot(1100, {me}), const Slot(220, {me})], 1320);
    expect(r, {me: 1320});
  });

  test('untracked item: your share is your part of the total, nobody is charged for the rest', () {
    final r = splitTotals([const Slot(1000, {me}), const Slot(1000, {})], 2200); // total has 2.00 of tax
    expect(r, {me: 1100});
  });

  test('chicken rice: 3 rice, 2 tea, 1 sg rice, no tax, split between three people', () {
    final slots = [
      const Slot(1100, {me}),
      const Slot(1100, {'aiman'}),
      const Slot(1100, {'wei'}),
      const Slot(220, {me}),
      const Slot(220, {'aiman'}),
      const Slot(850, {'wei'}),
    ];
    final r = splitTotals(slots, 4590);
    expect(r[me], 1320);
    expect(r['aiman'], 1320);
    expect(r['wei'], 1950);
    expect(sum(r), 4590);
  });

  test('service charge and SST are shared in proportion and everything adds up', () {
    final slots = [const Slot(1000, {me}), const Slot(3000, {'a'}), const Slot(333, {'b'})];
    const total = 5099; // 4333 + 10% service + 6% SST + rounding
    final r = splitTotals(slots, total);
    expect(sum(r), total);
    expect(r['a']! > r['b']!, true);
    expect(r['a']! > r[me]!, true);
  });

  test('shared slot splits evenly, odd sen go to you', () {
    final r = splitTotals([const Slot(1001, {me, 'a'})], 1001);
    expect(r[me], 501);
    expect(r['a'], 500);
    expect(sum(r), 1001);
  });

  test('three way split of a bill with a leftover sen', () {
    final r = splitTotals([const Slot(1000, {me, 'a', 'b'})], 1000);
    expect(r[me], 334);
    expect(r['a'], 333);
    expect(r['b'], 333);
  });

  test('treat: the friend owes nothing and it all lands on you', () {
    final r = splitTotals([const Slot(400, {me, 'a'}, treat: true), const Slot(1000, {'a'})], 1400);
    expect(r[me], 400);
    expect(r['a'], 1000);
  });

  test('nothing ticked gives you zero; no items gives you the total', () {
    expect(splitTotals([const Slot(500, {})], 500), {me: 0});
    expect(splitTotals([], 777), {me: 777});
  });

  test('evenSplit', () {
    expect(evenSplit(1000, 3), [334, 333, 333]);
    expect(evenSplit(-1000, 3), [-333, -333, -334]);
    expect(evenSplit(5, 0), isEmpty);
  });

  group('ledger', () {
    Ledger sample() => Ledger(
          friends: [Friend(id: 'a', name: 'Aiman', phone: '012-345 6789'), Friend(id: 'b', name: 'Wei')],
          debts: [
            Debt(id: 'd1', friendId: 'a', date: '2026-11-01', title: 'Mamak', cents: 1000, items: ['Teh', 'Roti']),
            Debt(id: 'd2', friendId: 'a', date: '2026-11-06', title: 'Chicken Rice', cents: 1320, items: ['烧鸡饭 x1']),
            Debt(id: 'd3', friendId: 'b', date: '2026-11-06', title: 'Chicken Rice', cents: 1950),
          ],
          payments: [Payment(id: 'p1', friendId: 'a', date: '2026-11-07', cents: 1500)],
        );

    test('balances and total owed', () {
      final l = sample();
      expect(l.balanceOf('a'), 820);
      expect(l.balanceOf('b'), 1950);
      expect(l.totalOwed, 2770);
    });

    test('payments clear the oldest bill first', () {
      final open = sample().openDebts('a');
      expect(open[0].leftCents, 0);
      expect(open[0].settled, true);
      expect(open[1].leftCents, 820);
    });

    test('overpaying shows as credit', () {
      final l = sample()..payments.add(Payment(id: 'p2', friendId: 'b', date: '2026-11-08', cents: 2000));
      expect(l.balanceOf('b'), -50);
      expect(l.totalOwed, 820);
    });

    test('json round trip', () {
      final l = sample();
      final back = Ledger.decode(l.encode());
      expect(back.friends.length, 2);
      expect(back.friends.first.phone, '012-345 6789');
      expect(back.debts[1].items, ['烧鸡饭 x1']);
      expect(back.balanceOf('a'), 820);
    });

    test('how a bill was split survives a round trip', () {
      final l = sample();
      l.splits['t1'] = {
        'att': ['a'],
        'treatAll': false,
        'lines': [
          {'n': 'Rice', 'q': 2, 'u': 1100, 'p': [['me'], ['a']], 't': [false, false]},
        ],
      };
      final back = Ledger.decode(l.encode());
      expect(back.splits['t1']!['att'], ['a']);
      expect((back.splits['t1']!['lines'] as List).length, 1);
      expect(Ledger.decode('{"friends":[],"debts":[],"payments":[]}').splits, isEmpty);
    });

    test('bad json gives an empty ledger', () {
      expect(Ledger.decode('not json').friends, isEmpty);
      expect(Ledger.decode(null).debts, isEmpty);
    });

    test('whatsapp numbers', () {
      expect(whatsappNumber('012-345 6789'), '60123456789');
      expect(whatsappNumber('+60 12 345 6789'), '60123456789');
      expect(whatsappNumber('0060123456789'), '60123456789');
      expect(whatsappNumber('123'), isNull);
      expect(whatsappNumber(null), isNull);
    });

    test('reminder lists unpaid bills with items and the pay link', () {
      final l = sample();
      final msg = reminderMessage(name: 'Aiman', open: l.openDebts('a'), payLink: 'https://pay.example/x');
      expect(msg.contains('RM 8.20'), true);
      expect(msg.contains('6 Nov Chicken Rice'), true);
      expect(msg.contains('烧鸡饭 x1'), true);
      expect(msg.contains('Mamak'), false); // already covered by the payment
      expect(msg.contains('https://pay.example/x'), true);
    });

    test('nothing owed gives a short thanks', () {
      final l = Ledger(friends: [Friend(id: 'a', name: 'A')]);
      expect(reminderMessage(name: 'A', open: l.openDebts('a')), contains('settled'));
    });
  });
}

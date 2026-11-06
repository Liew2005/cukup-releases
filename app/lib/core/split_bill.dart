// Splitting a bill between you and your friends. Pure maths, no Flutter.
//
// A bill is a list of [Slot]s: one slot per unit ordered (3 plates of rice = 3 slots).
// Each slot says who had it. Several people on one slot share it evenly.
// Tax, service charge and rounding are then spread in proportion to what each person had,
// so everybody's total adds up to the receipt to the sen.

/// The person id used for yourself.
const me = 'me';

class Slot {
  const Slot(this.cents, this.people, {this.treat = false});

  /// Price of this one unit, in cents.
  final int cents;

  /// Who had it. Empty means nobody you are tracking (for example a stranger's order): not yours, not owed.
  final Set<String> people;

  /// You are paying for the friends on this slot: they owe nothing and it counts as your spending.
  final bool treat;
}

int _floorDiv(int a, int b) {
  final q = a ~/ b;
  return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q;
}

/// Splits [total] cents between [ids] as evenly as possible. Leftover sen go to [first] (you), then in list order.
List<int> evenSplit(int total, int count) {
  if (count <= 0) return const [];
  final base = _floorDiv(total, count);
  final rest = total - base * count;
  return [for (var i = 0; i < count; i++) base + (i < rest ? 1 : 0)];
}

/// What each person had of one slot, before tax. A treat puts the whole slot on you.
Map<String, int> slotShares(Slot s) {
  if (s.people.isEmpty) return const {};
  if (s.treat) return {me: s.cents};
  final ids = [if (s.people.contains(me)) me, ...(s.people.where((p) => p != me).toList()..sort())];
  final parts = evenSplit(s.cents, ids.length);
  return {for (var i = 0; i < ids.length; i++) ids[i]: parts[i]};
}

/// What each person pays of the receipt [totalCents], tax and rounding included.
/// A slot nobody is tracking still takes its part of the tax, but nobody is charged for it.
Map<String, int> splitTotals(List<Slot> slots, int totalCents) {
  final all = slots.fold<int>(0, (s, x) => s + x.cents);
  if (slots.isEmpty || all <= 0) return {me: totalCents};

  final amounts = <String, int>{};
  for (final s in slots) {
    slotShares(s).forEach((p, c) => amounts[p] = (amounts[p] ?? 0) + c);
  }
  if (amounts.isEmpty) return {me: 0};

  final people = [if (amounts.containsKey(me)) me, ...(amounts.keys.where((p) => p != me).toList()..sort())];
  final floors = <String, int>{};
  final fractions = <String, int>{}; // remainder out of `all`
  var rawSum = 0.0;
  for (final p in people) {
    final num = totalCents * amounts[p]!;
    final f = _floorDiv(num, all);
    floors[p] = f;
    fractions[p] = num - f * all;
    rawSum += num / all;
  }
  var left = rawSum.round() - floors.values.fold<int>(0, (a, b) => a + b);
  final order = [...people]..sort((a, b) => fractions[b]!.compareTo(fractions[a]!)); // stable: you come first on ties
  final out = {...floors};
  for (final p in order) {
    if (left <= 0) break;
    out[p] = out[p]! + 1;
    left--;
  }
  return out;
}

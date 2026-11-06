/// Your share of a shared receipt.
///
/// Tax, service charge and rounding are split in proportion to the items you kept, so
/// ticking every item gives exactly the receipt total. Never more than the total, never negative.
int yourShare({required int totalCents, required List<({int priceCents, bool included})> items}) {
  final itemsSum = items.fold<int>(0, (s, i) => s + i.priceCents);
  if (items.isEmpty || itemsSum <= 0) return totalCents;
  final includedSum = items.where((i) => i.included).fold<int>(0, (s, i) => s + i.priceCents);
  if (includedSum <= 0) return 0;
  if (items.every((i) => i.included)) return totalCents;
  final share = (totalCents * includedSum / itemsSum).round();
  return share.clamp(0, totalCents);
}

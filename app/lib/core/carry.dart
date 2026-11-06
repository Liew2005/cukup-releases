/// How much of the weekly cap is available this week after overspending is carried forward.
class CapInfo {
  const CapInfo({required this.base, required this.effective});
  final int base;
  final int effective;
  int get carried => base - effective;
}

/// Carry overspending into later weeks.
/// [pastSpent] is counted spending for each earlier week, oldest first, ending with last week.
/// Overspending (spent above that week's available cap) becomes debt. Each week takes at most
/// [maxShare] of the base cap off to pay the debt back; whatever is left rolls on to the next week.
/// Underspending never adds to a later week (leftover money goes to the savings sweep instead).
CapInfo carryOver({required int base, required List<int> pastSpent, double maxShare = 0.5}) {
  if (base <= 0) return CapInfo(base: base, effective: base);
  final maxCut = (base * maxShare).floor();
  var debt = 0;
  for (final spent in pastSpent) {
    final cut = debt < maxCut ? debt : maxCut;
    final available = base - cut;
    final over = spent > available ? spent - available : 0;
    debt = debt - cut + over;
  }
  final cut = debt < maxCut ? debt : maxCut;
  return CapInfo(base: base, effective: base - cut);
}

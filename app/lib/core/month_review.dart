import '../data/db.dart';
import 'time.dart';

/// How one calendar month went. All amounts are whole cents.
class MonthReview {
  const MonthReview({
    required this.month,
    required this.spentCents,
    required this.prevSpentCents,
    required this.incomeCents,
    required this.outsideCapCents,
    required this.entries,
    required this.topCategories,
    required this.biggest,
    required this.weeksUnderCap,
    required this.weeksCounted,
    required this.sweptCents,
  });
  final String month; // YYYY-MM
  final int spentCents;
  final int prevSpentCents; // the month before, for comparison
  final int incomeCents;
  final int outsideCapCents; // spending the weekly cap ignored (bills and the like)
  final int entries;
  final List<({int categoryId, int cents})> topCategories; // biggest first
  final Txn? biggest; // the largest single spend
  final int weeksUnderCap; // weeks that ended in this month at or under the cap
  final int weeksCounted; // weeks that ended in this month and are already over
  final int sweptCents; // set aside toward the savings goal from those weeks

  /// Money in minus money out. Negative when more went out than came in.
  int get keptCents => incomeCents - spentCents;

  /// Spending compared with the month before: positive means you spent more. Null when there is nothing to compare.
  int? get changeCents => prevSpentCents == 0 ? null : spentCents - prevSpentCents;
}

String _prevMonth(String month) => addDays('$month-01', -1).substring(0, 7);

/// The month before / after [month] (YYYY-MM).
String shiftMonth(String month, int by) {
  var y = int.parse(month.substring(0, 4));
  var m = int.parse(month.substring(5, 7)) + by;
  while (m < 1) {
    m += 12;
    y--;
  }
  while (m > 12) {
    m -= 12;
    y++;
  }
  return '${y.toString().padLeft(4, '0')}-${m.toString().padLeft(2, '0')}';
}

/// "November 2026"
String monthName(String month) {
  const names = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  return '${names[int.parse(month.substring(5, 7)) - 1]} ${month.substring(0, 4)}';
}

/// Sums up [month] from all entries. [capCents] is the weekly cap, [sweeps] maps a week's Monday to cents set aside,
/// and [today] keeps a week that has not finished yet out of the under-the-cap count.
MonthReview reviewMonth(List<Txn> txns, String month, {required int capCents, required String today, Map<String, int> sweeps = const {}}) {
  final prev = _prevMonth(month);
  var spent = 0, prevSpent = 0, income = 0, outside = 0, entries = 0;
  final byCat = <int, int>{};
  final capByWeek = <String, int>{}; // Monday -> spending that counted toward the cap
  Txn? biggest;
  for (final t in txns) {
    if (t.deletedAt != null) continue;
    final m = t.spentAt.substring(0, 7);
    if (t.direction == 'spend' && t.countsTowardCap) capByWeek.update(mondayOf(t.spentAt), (v) => v + t.amountCents, ifAbsent: () => t.amountCents);
    if (m == prev && t.direction == 'spend') prevSpent += t.amountCents;
    if (m != month) continue;
    entries++;
    if (t.direction == 'income') {
      income += t.amountCents;
      continue;
    }
    spent += t.amountCents;
    if (!t.countsTowardCap) outside += t.amountCents;
    byCat.update(t.categoryId, (v) => v + t.amountCents, ifAbsent: () => t.amountCents);
    if (biggest == null || t.amountCents > biggest.amountCents) biggest = t;
  }

  // A week belongs to the month its Sunday falls in.
  var under = 0, counted = 0, swept = 0;
  final last = addDays(nextFirst('$month-01'), -1);
  for (var monday = mondayOf('$month-01'); monday.compareTo(last) <= 0; monday = addDays(monday, 7)) {
    final sunday = addDays(monday, 6);
    if (sunday.substring(0, 7) != month) continue;
    swept += sweeps[monday] ?? 0;
    if (sunday.compareTo(today) >= 0) continue; // still running
    counted++;
    if (capCents > 0 && (capByWeek[monday] ?? 0) <= capCents) under++;
  }

  final top = [for (final e in byCat.entries) (categoryId: e.key, cents: e.value)]..sort((a, b) => b.cents.compareTo(a.cents));
  return MonthReview(month: month, spentCents: spent, prevSpentCents: prevSpent, incomeCents: income, outsideCapCents: outside, entries: entries, topCategories: top, biggest: biggest, weeksUnderCap: under, weeksCounted: counted, sweptCents: swept);
}

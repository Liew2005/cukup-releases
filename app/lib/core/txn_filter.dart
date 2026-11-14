import '../data/db.dart';
import 'time.dart';

/// What the Activity screen is narrowed down to. Everything left at its default shows all entries.
class TxnFilter {
  const TxnFilter({this.query = '', this.direction = 'all', this.categoryId, this.period = 'all', this.from, this.to, this.paymentType, this.outsideCap = false});
  final String query; // matches shop, note or category name
  final String direction; // all | spend | income
  final int? categoryId;
  final String period; // all | week | month | last_month | custom
  final String? from; // YYYY-MM-DD, used when period is custom
  final String? to;
  final String? paymentType; // cash | debit | ewallet | credit_card | spaylater
  final bool outsideCap; // only spending that does not count toward the weekly cap

  /// True when the sheet's filters (not the search box or the chips above the list) are narrowing the list.
  bool get hasExtra => period != 'all' || paymentType != null || outsideCap;
  bool get isActive => hasExtra || query.trim().isNotEmpty || direction != 'all' || categoryId != null;

  TxnFilter copyWith({String? query, String? direction, int? Function()? categoryId, String? period, String? Function()? from, String? Function()? to, String? Function()? paymentType, bool? outsideCap}) => TxnFilter(
        query: query ?? this.query,
        direction: direction ?? this.direction,
        categoryId: categoryId == null ? this.categoryId : categoryId(),
        period: period ?? this.period,
        from: from == null ? this.from : from(),
        to: to == null ? this.to : to(),
        paymentType: paymentType == null ? this.paymentType : paymentType(),
        outsideCap: outsideCap ?? this.outsideCap,
      );
}

/// First and last day (inclusive) a period covers, or null for "all time". Weeks run Monday to Sunday.
({String from, String to})? periodRange(TxnFilter f, String today) {
  switch (f.period) {
    case 'week':
      final mon = mondayOf(today);
      return (from: mon, to: addDays(mon, 6));
    case 'month':
      final first = firstOfMonth(today);
      return (from: first, to: addDays(nextFirst(today), -1));
    case 'last_month':
      final lastDay = addDays(firstOfMonth(today), -1);
      return (from: firstOfMonth(lastDay), to: lastDay);
    case 'custom':
      if (f.from == null && f.to == null) return null;
      return (from: f.from ?? '0000-01-01', to: f.to ?? '9999-12-31');
    default:
      return null;
  }
}

/// The entries that pass the filter, in the order given. [categoryNames] lets the search box match a category.
List<Txn> applyFilter(List<Txn> txns, TxnFilter f, {required String today, Map<int, String> categoryNames = const {}}) {
  final q = f.query.trim().toLowerCase();
  final range = periodRange(f, today);
  return [
    for (final t in txns)
      if ((f.direction == 'all' || t.direction == f.direction) &&
          (f.categoryId == null || t.categoryId == f.categoryId) &&
          (f.paymentType == null || (t.direction == 'spend' && t.paymentType == f.paymentType)) &&
          (!f.outsideCap || (t.direction == 'spend' && !t.countsTowardCap)) &&
          (range == null || (t.spentAt.compareTo(range.from) >= 0 && t.spentAt.compareTo(range.to) <= 0)) &&
          (q.isEmpty || '${t.merchant} ${t.note ?? ''} ${categoryNames[t.categoryId] ?? ''}'.toLowerCase().contains(q)))
        t,
  ];
}

/// How many entries, and how much went out and came in.
({int count, int spentCents, int incomeCents}) totalsOf(List<Txn> txns) {
  var spent = 0, income = 0;
  for (final t in txns) {
    if (t.direction == 'income') {
      income += t.amountCents;
    } else {
      spent += t.amountCents;
    }
  }
  return (count: txns.length, spentCents: spent, incomeCents: income);
}

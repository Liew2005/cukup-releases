import '../data/db.dart';

/// A spreadsheet treats cells starting with = + - @ as formulas, so those get a leading apostrophe.
String csvCell(String? v) {
  var s = v ?? '';
  if (s.isNotEmpty && '=+-@\t\r'.contains(s[0])) s = "'$s";
  if (s.contains(',') || s.contains('"') || s.contains('\n') || s.contains('\r')) s = '"${s.replaceAll('"', '""')}"';
  return s;
}

String _money(int cents) => '${cents < 0 ? '-' : ''}${(cents.abs() ~/ 100)}.${(cents.abs() % 100).toString().padLeft(2, '0')}';

/// One row per entry: date, where, type, category, amount in RM, paid with, counts toward cap, note, source.
String buildCsv(List<Txn> txns, Map<int, String> categoryNames) {
  final out = StringBuffer('date,merchant,type,category,amount_rm,payment,counts_toward_cap,note,source\r\n');
  for (final t in txns) {
    out.write([
      t.spentAt,
      csvCell(t.merchant),
      t.direction,
      csvCell(categoryNames[t.categoryId] ?? ''),
      _money(t.amountCents), // never starts with a minus sign worth guarding: amounts are positive
      t.paymentType,
      t.countsTowardCap ? 'yes' : 'no',
      csvCell(t.note),
      t.source,
    ].join(','));
    out.write('\r\n');
  }
  return out.toString();
}

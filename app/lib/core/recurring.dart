/// Month arithmetic on YYYY-MM strings.
String shiftMonth(String ym, int by) {
  final total = int.parse(ym.substring(0, 4)) * 12 + (int.parse(ym.substring(5, 7)) - 1) + by;
  return '${(total ~/ 12).toString().padLeft(4, '0')}-${(total % 12 + 1).toString().padLeft(2, '0')}';
}

/// The months (YYYY-MM, oldest first) that still need an entry for a repeating item that falls on [day] each month.
/// A month is due once its day has arrived. After the app is closed for a while this returns every missed month,
/// at most the last 12, so nothing is lost and nothing is posted twice (ids are fixed per item and month).
List<String> dueMonths({required String today, required int day, required String? lastPosted}) {
  final current = today.substring(0, 7);
  final todayDay = int.parse(today.substring(8, 10));
  final earliest = shiftMonth(current, -11);
  var m = lastPosted == null ? current : shiftMonth(lastPosted, 1);
  if (m.compareTo(earliest) < 0) m = earliest;
  final out = <String>[];
  while (m.compareTo(current) <= 0) {
    if (m.compareTo(current) < 0 || todayDay >= day) out.add(m);
    m = shiftMonth(m, 1);
  }
  return out;
}

// Dates are plain YYYY-MM-DD strings in Malaysia time (UTC+8), matching the server.

/// ISO 8601 UTC with millisecond precision, e.g. 2026-11-04T15:00:00.123Z.
String nowIso() => DateTime.fromMillisecondsSinceEpoch(DateTime.now().millisecondsSinceEpoch, isUtc: true).toIso8601String();

String ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String todayKL() => ymd(DateTime.now().toUtc().add(const Duration(hours: 8)));

DateTime parseYmd(String s) => DateTime.utc(int.parse(s.substring(0, 4)), int.parse(s.substring(5, 7)), int.parse(s.substring(8, 10)));

String addDays(String date, int n) => ymd(parseYmd(date).add(Duration(days: n)));

String mondayOf(String date) => addDays(date, -(parseYmd(date).weekday - 1));

/// The 1st of the month after [date]'s month (SPayLater dues land on the 1st).
String nextFirst(String date) {
  final d = parseYmd(date);
  return ymd(DateTime.utc(d.year, d.month + 1, 1));
}

/// The 1st of [date]'s own month.
String firstOfMonth(String date) => '${date.substring(0, 7)}-01';

/// Whole days from [a] to [b] (negative when b is earlier).
int daysBetween(String a, String b) => parseYmd(b).difference(parseYmd(a)).inDays;

/// Days from [date] to the Sunday that ends its week (0 on Sunday).
int daysToWeekEnd(String date) => 7 - parseYmd(date).weekday;

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
String shortDate(String date) {
  final d = parseYmd(date);
  return '${d.day} ${_months[d.month - 1]}';
}

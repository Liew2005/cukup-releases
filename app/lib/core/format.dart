import 'package:intl/intl.dart';

final _num = NumberFormat('#,##0.00', 'en_US');

/// 1234 -> "RM 12.34". Negative amounts get a leading minus.
String rm(int cents, {bool plus = false}) {
  final sign = cents < 0 ? '-' : (plus ? '+' : '');
  return '${sign}RM ${_num.format(cents.abs() / 100)}';
}

/// "12", "12.5", "RM 1,234.50" -> whole cents. Null if it is not a clean amount.
int? parseCents(String input) {
  final t = input.replaceAll(RegExp(r'[^0-9.]'), '');
  if (t.isEmpty) return null;
  final parts = t.split('.');
  if (parts.length > 2) return null;
  final whole = int.tryParse(parts[0].isEmpty ? '0' : parts[0]);
  if (whole == null) return null;
  final frac = parts.length == 2 ? parts[1] : '';
  if (frac.length > 2) return null;
  return whole * 100 + int.parse(frac.padRight(2, '0'));
}

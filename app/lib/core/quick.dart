import '../data/db.dart';

/// A shop you use often, with what you last paid there.
class QuickMerchant {
  const QuickMerchant({required this.name, required this.count, required this.lastAmountCents, required this.categoryId, required this.paymentType});
  final String name;
  final int count;
  final int lastAmountCents;
  final int categoryId;
  final String paymentType;
}

/// The [limit] most-used merchants among spending entries. [txns] must be newest first (as the database returns them),
/// so the first entry seen for a shop gives its last amount, category and payment. Ties go to the more recent shop.
List<QuickMerchant> topMerchants(List<Txn> txns, {int limit = 6}) {
  final counts = <String, int>{};
  final latest = <String, Txn>{};
  final order = <String>[];
  for (final t in txns) {
    if (t.direction != 'spend' || t.source == 'recurring') continue;
    final key = t.merchant.trim().toLowerCase();
    if (key.isEmpty) continue;
    counts[key] = (counts[key] ?? 0) + 1;
    if (!latest.containsKey(key)) {
      latest[key] = t;
      order.add(key);
    }
  }
  final keys = [...order]..sort((a, b) {
      final byCount = counts[b]!.compareTo(counts[a]!);
      return byCount != 0 ? byCount : order.indexOf(a).compareTo(order.indexOf(b));
    });
  return [
    for (final k in keys.take(limit))
      QuickMerchant(name: latest[k]!.merchant.trim(), count: counts[k]!, lastAmountCents: latest[k]!.amountCents, categoryId: latest[k]!.categoryId, paymentType: latest[k]!.paymentType),
  ];
}

/// Keypad input for the amount. Returns the new text after pressing [key]: a digit, '.', or 'back'.
/// At most 2 decimals and 7 whole digits; no leading zeros.
String applyKey(String text, String key) {
  if (key == 'back') return text.isEmpty ? text : text.substring(0, text.length - 1);
  if (key == '.') {
    if (text.contains('.')) return text;
    return text.isEmpty ? '0.' : '$text.';
  }
  final dot = text.indexOf('.');
  if (dot >= 0) return text.length - dot - 1 >= 2 ? text : '$text$key';
  if (text.length >= 7) return text;
  if (text == '0') return key == '0' ? text : key;
  return '$text$key';
}

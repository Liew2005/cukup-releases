import '../data/db.dart';
import 'time.dart';

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9一-鿿]'), '');

/// An existing entry that looks like the one about to be saved, or null.
/// A match is the same reference, or the same amount at the same shop within 36 hours
/// (the same day, or the day before or after, so a late-night entry still matches).
/// [recent] is any list of entries; deleted ones and [ignoreId] are skipped.
Txn? findDuplicate(List<Txn> recent, {required String merchant, required int amountCents, required String date, String? reference, String? ignoreId, String direction = 'spend'}) {
  final key = _norm(merchant);
  for (final t in recent) {
    if (t.id == ignoreId || t.deletedAt != null || t.direction != direction) continue;
    if (reference != null && reference.isNotEmpty && t.reference == reference) return t;
    if (t.amountCents == amountCents && key.isNotEmpty && _norm(t.merchant) == key && daysBetween(t.spentAt, date).abs() <= 1) return t;
  }
  return null;
}

/// Money left under the cap for a finished week, or null when there is nothing to sweep (over the cap, exactly on it, or no cap).
int? sweepable({required int capCents, required int spentCents}) {
  if (capCents <= 0) return null;
  final left = capCents - spentCents;
  return left > 0 ? left : null;
}

/// 0..1 progress toward a savings goal.
double goalProgress({required int savedCents, required int targetCents}) => targetCents <= 0 ? 0 : (savedCents / targetCents).clamp(0, 1).toDouble();

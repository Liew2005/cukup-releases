import 'package:drift/drift.dart' show Value;

import '../core/recurring.dart';
import '../core/time.dart';
import 'db.dart';

/// Creates the entries that repeating items owe, including months missed while the app was closed.
/// Each entry has a fixed id (item + month), so running this twice, or on two phones, never doubles one.
/// An entry you deleted stays deleted. Returns how many entries were created.
Future<int> postDueRecurring(AppDatabase db) async {
  final today = todayKL();
  var created = 0;
  for (final r in await db.getRecurringAll()) {
    if (!r.active) continue;
    final months = dueMonths(today: today, day: r.dayOfMonth, lastPosted: r.lastPosted);
    if (months.isEmpty) continue;
    for (final m in months) {
      final id = 'rec-${r.id}-$m';
      if (await db.getTxn(id) != null) continue;
      final now = nowIso();
      final spend = r.direction == 'spend';
      await db.saveTxn(
        TxnsCompanion.insert(
          id: id,
          spentAt: '$m-${r.dayOfMonth.toString().padLeft(2, '0')}',
          merchant: r.title,
          amountCents: r.amountCents,
          categoryId: r.categoryId,
          paymentType: r.paymentType,
          createdAt: now,
          updatedAt: now,
          direction: Value(r.direction),
          countsTowardCap: Value(spend && r.paymentType != 'spaylater' && r.countsTowardCap),
          source: const Value('recurring'),
        ),
        const [],
      );
      created++;
    }
    await db.setRecurringPosted(r.id, months.last);
  }
  return created;
}

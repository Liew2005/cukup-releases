import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../core/carry.dart';
import '../core/time.dart';
import 'db.dart';
import 'providers.dart';

const _lookbackWeeks = 4;

/// Available cap for the week starting [monday] (default: this week), with earlier overspending carried in.
/// Worked out from the entries each time, so editing or deleting a past entry corrects it.
Future<CapInfo> loadCapInfo(AppDatabase db, {String? monday}) async {
  final base = int.tryParse(await db.getKv('setting.weekly_cap_cents') ?? '') ?? 25000;
  if (await db.getKv('setting.carry') == '0') return CapInfo(base: base, effective: base);
  final start = monday ?? mondayOf(todayKL());
  final past = <int>[for (var k = _lookbackWeeks; k >= 1; k--) await db.weekSpentFor(addDays(start, -7 * k))];
  return carryOver(base: base, pastSpent: past);
}

final carryTickProvider = StateProvider<int>((ref) => 0);

/// This week's available cap. Refreshes when entries, the cap or the carry-over switch change.
final capInfoProvider = FutureProvider.autoDispose<CapInfo>((ref) async {
  ref.watch(carryTickProvider);
  ref.watch(capCentsProvider);
  ref.watch(weekSpentProvider);
  ref.watch(recentTxnsProvider); // a backdated or deleted entry in an earlier week changes the carry
  return loadCapInfo(ref.read(dbProvider));
});

Future<void> setCarryOver(WidgetRef ref, bool on) async {
  await ref.read(dbProvider).setKv('setting.carry', on ? '1' : '0');
  ref.read(carryTickProvider.notifier).state++;
}

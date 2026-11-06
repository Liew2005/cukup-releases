import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../core/guards.dart';
import '../core/time.dart';
import 'carry.dart';
import 'providers.dart';

/// Week-end sweep: money you did not spend under last week's cap, moved toward a savings goal.
/// Stored on this phone only (like merchant rules): `sweep.<monday>` = cents swept, `sweepskip.<monday>`, `goal.name`, `goal.target_cents`.
class SweepState {
  const SweepState({this.goalName, this.goalTargetCents = 0, this.savedCents = 0, this.offerCents, required this.lastMonday});
  final String? goalName;
  final int goalTargetCents;
  final int savedCents;
  final int? offerCents; // under-cap amount from last week waiting for a yes or no; null when there is nothing to offer
  final String lastMonday;
  bool get hasGoal => goalName != null && goalTargetCents > 0;
}

final sweepTickProvider = StateProvider<int>((ref) => 0);

final sweepProvider = FutureProvider.autoDispose<SweepState>((ref) async {
  ref.watch(sweepTickProvider);
  ref.watch(weekSpentProvider); // re-check when entries change
  final db = ref.read(dbProvider);
  final lastMonday = addDays(mondayOf(todayKL()), -7);
  final name = await db.getKv('goal.name');
  final target = int.tryParse(await db.getKv('goal.target_cents') ?? '') ?? 0;
  final saved = (await db.kvValuesWithPrefix('sweep.')).fold<int>(0, (s, v) => s + (int.tryParse(v) ?? 0));
  int? offer;
  final goalSet = name != null && target > 0;
  if (goalSet && await db.getKv('sweep.$lastMonday') == null && await db.getKv('sweepskip.$lastMonday') == null) {
    final cap = (await loadCapInfo(db, monday: lastMonday)).effective; // last week's available cap, carry included
    final spent = await db.weekSpentFor(lastMonday);
    if (spent > 0) offer = sweepable(capCents: cap, spentCents: spent); // a week with nothing logged proves nothing
  }
  return SweepState(goalName: name, goalTargetCents: target, savedCents: saved, offerCents: offer, lastMonday: lastMonday);
});

Future<void> doSweep(WidgetRef ref, SweepState s) async {
  final offer = s.offerCents;
  if (offer == null) return;
  await ref.read(dbProvider).setKv('sweep.${s.lastMonday}', '$offer');
  ref.read(sweepTickProvider.notifier).state++;
}

Future<void> skipSweep(WidgetRef ref, SweepState s) async {
  await ref.read(dbProvider).setKv('sweepskip.${s.lastMonday}', '1');
  ref.read(sweepTickProvider.notifier).state++;
}

Future<void> saveGoal(WidgetRef ref, String name, int targetCents) async {
  final db = ref.read(dbProvider);
  await db.setKv('goal.name', name);
  await db.setKv('goal.target_cents', '$targetCents');
  ref.read(sweepTickProvider.notifier).state++;
}

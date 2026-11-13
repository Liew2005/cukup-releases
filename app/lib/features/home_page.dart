import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/format.dart';
import '../core/time.dart';
import '../data/carry.dart';
import '../data/providers.dart';
import '../data/recurring_poster.dart';
import '../data/share_import.dart';
import '../data/widget_sync.dart';
import '../theme/theme.dart';
import 'detected_card.dart';
import 'friends_page.dart';
import 'sweep_cards.dart';
import 'week_bars.dart';
import 'widgets.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});
  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      ref.read(notificationsProvider); // starts reminders
      ref.read(widgetSyncProvider); // keeps the home-screen widget current
      ref.read(shareImportProvider); // screenshots shared from TnG or the bank
      await postDueRecurring(ref.read(dbProvider)).catchError((_) => 0); // works offline; sync pushes the result
      ref.read(syncProvider.notifier).run();
    });
  }

  @override
  Widget build(BuildContext context) {
    final today = todayKL();
    final info = ref.watch(capInfoProvider).asData?.value;
    final cap = info?.effective ?? ref.watch(capCentsProvider).asData?.value ?? 25000;
    final carried = info?.carried ?? 0;
    final spent = ref.watch(weekSpentProvider).asData?.value ?? 0;
    final recent = ref.watch(recentTxnsProvider).asData?.value ?? const [];
    final sync = ref.watch(syncProvider);
    final pending = ref.watch(pendingCountProvider).asData?.value ?? 0;
    final left = cap - spent;
    final over = left < 0;
    final days = daysToWeekEnd(today);

    final status = sync.running
        ? 'Syncing…'
        : sync.error != null
            ? (pending > 0 ? '${sync.error} · $pending waiting' : sync.error!)
            : (pending > 0 ? '$pending waiting' : 'Synced');

    return SafeArea(
      child: RefreshIndicator(
        color: Brand.forest,
        onRefresh: () => ref.read(syncProvider.notifier).run(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Week of ${shortDate(mondayOf(today))}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Brand.muted)),
              Row(children: [
                Text(status, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: sync.error != null ? Brand.danger : Brand.muted)),
                IconButton(icon: const Icon(Icons.tune_rounded), tooltip: 'Settings', onPressed: () => context.push('/settings')),
              ]),
            ]),
            const SizedBox(height: 14),
            Text(over ? 'Over the cap by' : 'Left this week', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Brand.muted)),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(rm(left.abs()), style: TextStyle(fontSize: 60, fontWeight: FontWeight.w800, letterSpacing: -2.5, height: 1, color: over ? Brand.danger : Brand.forest)),
            ),
            const SizedBox(height: 10),
            Text('of ${rm(cap)}${carried > 0 ? ' (${rm(carried)} carried over)' : ''} · ${days == 0 ? 'last day' : '$days ${days == 1 ? 'day' : 'days'} to go'}', style: const TextStyle(fontSize: 15, color: Brand.muted)),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(value: cap == 0 ? 0 : (spent / cap).clamp(0, 1).toDouble(), minHeight: 8, backgroundColor: Brand.line, color: over ? Brand.danger : Brand.forest),
            ),
            const SizedBox(height: 22),
            const DetectedCard(),
            const SweepOfferCard(),
            WeekBars(daily: ref.watch(weekDailyProvider).asData?.value ?? const {}, capCents: cap, today: today),
            const SizedBox(height: 22),
            FilledButton(onPressed: () => context.push('/quick'), child: const Text('+ Quick add')),
            const SizedBox(height: 12),
            const FriendsCard(),
            const SizedBox(height: 26),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
              const Text('Latest', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              TextButton(onPressed: () => context.go('/activity'), child: const Text('See all', style: TextStyle(color: Brand.forest, fontWeight: FontWeight.w600))),
            ]),
            if (recent.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(vertical: 28), child: Text('Nothing logged yet. Tap Quick add to start.', style: TextStyle(color: Brand.muted)))
            else
              for (final t in recent) TxnTile(txn: t),
          ],
        ),
      ),
    );
  }
}

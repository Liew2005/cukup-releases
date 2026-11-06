import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import '../core/guards.dart';
import '../data/sweeps.dart';
import '../theme/theme.dart';

/// Home: "you came in RM x under last week, move it to your goal?" Shows nothing for an over-cap week.
class SweepOfferCard extends ConsumerWidget {
  const SweepOfferCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sweepProvider).asData?.value;
    if (s == null || s.offerCents == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Brand.mint, borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('You finished last week ${rm(s.offerCents!)} under your cap', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Brand.forest)),
        const SizedBox(height: 4),
        Text('Move it to "${s.goalName}"?', style: const TextStyle(fontSize: 14, color: Brand.muted)),
        const SizedBox(height: 10),
        Row(children: [
          FilledButton(onPressed: () => doSweep(ref, s), style: FilledButton.styleFrom(minimumSize: const Size(0, 40)), child: const Text('Sweep it')),
          const SizedBox(width: 8),
          TextButton(onPressed: () => skipSweep(ref, s), child: const Text('Not this week', style: TextStyle(color: Brand.muted, fontWeight: FontWeight.w600))),
        ]),
      ]),
    );
  }
}

/// Bills: savings goal and how far the sweeps have got.
class GoalCard extends ConsumerWidget {
  const GoalCard({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, SweepState? s) async {
    final name = TextEditingController(text: s?.goalName ?? '');
    final target = TextEditingController(text: s != null && s.goalTargetCents > 0 ? (s.goalTargetCents / 100).toStringAsFixed(0) : '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Savings goal'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'What for')),
          const SizedBox(height: 10),
          TextField(controller: target, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Target', prefixText: 'RM ')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('Save', style: TextStyle(color: Brand.forest, fontWeight: FontWeight.w800))),
        ],
      ),
    );
    final cents = parseCents(target.text);
    if (ok == true && name.text.trim().isNotEmpty && cents != null && cents > 0) await saveGoal(ref, name.text.trim(), cents);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sweepProvider).asData?.value;
    if (s == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Brand.card, borderRadius: BorderRadius.circular(18), border: Border.all(color: Brand.line)),
      child: s.hasGoal
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(s.goalName!, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                TextButton(onPressed: () => _edit(context, ref, s), child: const Text('Edit', style: TextStyle(color: Brand.forest, fontWeight: FontWeight.w600))),
              ]),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(value: goalProgress(savedCents: s.savedCents, targetCents: s.goalTargetCents), minHeight: 8, backgroundColor: Brand.line, color: Brand.forest),
              ),
              const SizedBox(height: 8),
              Text('${rm(s.savedCents)} of ${rm(s.goalTargetCents)} saved from weeks under the cap', style: const TextStyle(fontSize: 13, color: Brand.muted)),
            ])
          : Row(children: [
              const Expanded(child: Text('Set a savings goal and Cukup will offer to move what you did not spend each week.', style: TextStyle(fontSize: 14, color: Brand.muted))),
              TextButton(onPressed: () => _edit(context, ref, null), child: const Text('Set goal', style: TextStyle(color: Brand.forest, fontWeight: FontWeight.w800))),
            ]),
    );
  }
}

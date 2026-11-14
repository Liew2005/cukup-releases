import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/format.dart';
import '../core/month_review.dart';
import '../core/time.dart';
import '../data/db.dart';
import '../data/ledger.dart';
import '../data/providers.dart';
import '../theme/theme.dart';

/// How a month went: spent, in, kept, where it went, the biggest purchase, weeks under the cap and what friends owe.
/// Opens on last month from the 1st-of-the-month reminder, and on this month from Insights.
class MonthReviewPage extends ConsumerStatefulWidget {
  const MonthReviewPage({super.key, this.month});
  final String? month; // YYYY-MM; this month when null
  @override
  ConsumerState<MonthReviewPage> createState() => _MonthReviewPageState();
}

class _MonthReviewPageState extends ConsumerState<MonthReviewPage> {
  late String _month = widget.month ?? todayKL().substring(0, 7);
  Map<String, int> _sweeps = const {};

  @override
  void initState() {
    super.initState();
    ref.read(dbProvider).kvPrefix('sweep.').then((m) {
      if (mounted) setState(() => _sweeps = {for (final e in m.entries) e.key.substring(6): int.tryParse(e.value) ?? 0});
    });
  }

  Widget _card({required Widget child}) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Brand.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: Brand.line)),
        child: child,
      );

  Widget _line(String label, String value, {Color? color, bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 15))),
          Text(value, style: TextStyle(fontSize: 15, fontWeight: bold ? FontWeight.w800 : FontWeight.w700, color: color ?? Brand.ink)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final today = todayKL();
    final thisMonth = today.substring(0, 7);
    final txns = ref.watch(txnsProvider).asData?.value ?? const <Txn>[];
    final cats = ref.watch(categoriesProvider).asData?.value ?? const <Cat>[];
    final names = {for (final c in cats) c.id: c.name};
    final cap = ref.watch(capCentsProvider).asData?.value ?? 0;
    final owed = ref.watch(ledgerProvider).totalOwed;
    final r = reviewMonth(txns, _month, capCents: cap, today: today, sweeps: _sweeps);
    final running = _month == thisMonth;
    final change = r.changeCents;
    const h = TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Brand.muted, letterSpacing: 0.4);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), tooltip: 'Back', onPressed: () => context.pop()),
        title: const Text('Month in review', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 28), children: [
          Row(children: [
            IconButton(icon: const Icon(Icons.chevron_left), tooltip: 'Earlier month', onPressed: () => setState(() => _month = shiftMonth(_month, -1))),
            Expanded(child: Text(monthName(_month), textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
            IconButton(icon: const Icon(Icons.chevron_right), tooltip: 'Later month', onPressed: running ? null : () => setState(() => _month = shiftMonth(_month, 1))),
          ]),
          const SizedBox(height: 8),
          if (r.entries == 0)
            _card(child: Text(running ? 'Nothing logged yet this month.' : 'Nothing was logged in ${monthName(_month)}.', style: const TextStyle(color: Brand.muted)))
          else ...[
            _card(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(running ? 'SPENT SO FAR' : 'SPENT', style: h),
                const SizedBox(height: 4),
                FittedBox(fit: BoxFit.scaleDown, child: Text(rm(r.spentCents), style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800, letterSpacing: -1.4, color: Brand.forest))),
                if (change != null)
                  Text(
                    change == 0 ? 'The same as ${monthName(shiftMonth(_month, -1))}' : '${rm(change.abs())} ${change > 0 ? 'more' : 'less'} than ${monthName(shiftMonth(_month, -1))}',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: change > 0 ? Brand.danger : Brand.forest),
                  ),
                const Divider(height: 24, color: Brand.line),
                _line('Money in', rm(r.incomeCents)),
                _line('Money out', rm(r.spentCents)),
                _line(r.keptCents >= 0 ? 'Kept' : 'Short by', rm(r.keptCents.abs()), color: r.keptCents >= 0 ? Brand.forest : Brand.danger, bold: true),
                if (r.outsideCapCents > 0) Padding(padding: const EdgeInsets.only(top: 6), child: Text('${rm(r.outsideCapCents)} of the spending was outside your weekly cap (bills and the like).', style: const TextStyle(fontSize: 12, color: Brand.muted))),
              ]),
            ),
            if (r.topCategories.isNotEmpty)
              _card(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('WHERE IT WENT', style: h),
                  const SizedBox(height: 6),
                  for (final c in r.topCategories.take(5))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text(names[c.categoryId] ?? 'Other', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
                          Text('${rm(c.cents)} · ${(c.cents * 100 / r.spentCents).round()}%', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                        ]),
                        const SizedBox(height: 5),
                        ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: c.cents / r.spentCents, minHeight: 6, backgroundColor: Brand.line, color: Brand.forest)),
                      ]),
                    ),
                ]),
              ),
            _card(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('HIGHLIGHTS', style: h),
                const SizedBox(height: 6),
                if (r.biggest != null) _line('Biggest purchase', '${rm(r.biggest!.amountCents)} · ${r.biggest!.merchant}'),
                if (r.weeksCounted > 0) _line('Weeks at or under your cap', '${r.weeksUnderCap} of ${r.weeksCounted}', color: r.weeksUnderCap == r.weeksCounted ? Brand.forest : null),
                if (r.sweptCents > 0) _line('Set aside for your goal', rm(r.sweptCents), color: Brand.forest),
                _line('Entries logged', '${r.entries}'),
                if (owed > 0) _line('Friends owe you now', rm(owed)),
              ]),
            ),
          ],
        ]),
      ),
    );
  }
}

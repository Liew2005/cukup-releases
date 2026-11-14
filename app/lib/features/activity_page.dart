import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import '../core/time.dart';
import '../core/txn_filter.dart';
import '../data/db.dart';
import '../data/ledger.dart';
import '../data/providers.dart';
import '../theme/theme.dart';
import 'chips.dart';
import 'widgets.dart';

const _periods = {'all': 'All time', 'week': 'This week', 'month': 'This month', 'last_month': 'Last month', 'custom': 'Pick dates'};
const _payments = {'cash': 'Cash', 'debit': 'Debit', 'ewallet': 'E-wallet', 'credit_card': 'Credit card', 'spaylater': 'SPayLater'};

class ActivityPage extends ConsumerStatefulWidget {
  const ActivityPage({super.key});
  @override
  ConsumerState<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends ConsumerState<ActivityPage> {
  final _search = TextEditingController();
  TxnFilter _f = const TxnFilter();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _dayLabel(String d, String today) {
    if (d == today) return 'Today';
    if (d == addDays(today, -1)) return 'Yesterday';
    return shortDate(d);
  }

  /// Period, paid with and "outside the cap": the filters that do not fit in the chip row.
  Future<void> _openFilters() async {
    var f = _f;
    final picked = await showModalBottomSheet<TxnFilter>(
      context: context,
      backgroundColor: Brand.paper,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (c) => StatefulBuilder(
        builder: (c, set) {
          Future<void> pickDates() async {
            final now = DateTime.now();
            final r = await showDateRangePicker(
              context: c,
              firstDate: DateTime(2020),
              lastDate: DateTime(now.year + 1, 12, 31),
              initialDateRange: f.from != null && f.to != null ? DateTimeRange(start: parseYmd(f.from!), end: parseYmd(f.to!)) : null,
              builder: (context, child) => Theme(data: Theme.of(context).copyWith(colorScheme: Theme.of(context).colorScheme.copyWith(primary: Brand.forest)), child: child!),
            );
            if (r != null) set(() => f = f.copyWith(period: 'custom', from: () => ymd(r.start), to: () => ymd(r.end)));
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Filters', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 14),
                const FieldLabel('When'),
                PickChips<String>(
                  options: _periods,
                  selected: f.period,
                  onSelected: (p) {
                    if (p == 'custom') {
                      pickDates();
                    } else {
                      set(() => f = f.copyWith(period: p, from: () => null, to: () => null));
                    }
                  },
                ),
                if (f.period == 'custom' && f.from != null && f.to != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('${shortDate(f.from!)} to ${shortDate(f.to!)}', style: const TextStyle(fontSize: 13, color: Brand.muted))),
                const SizedBox(height: 16),
                const FieldLabel('Paid with'),
                PickChips<String>(options: {'any': 'Any', ..._payments}, selected: f.paymentType ?? 'any', onSelected: (p) => set(() => f = f.copyWith(paymentType: () => p == 'any' ? null : p))),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Only outside the weekly cap'),
                  subtitle: const Text('Bills and other spending your week ignores', style: TextStyle(fontSize: 12, color: Brand.muted)),
                  value: f.outsideCap,
                  activeThumbColor: Brand.paper,
                  activeTrackColor: Brand.forest,
                  onChanged: (v) => set(() => f = f.copyWith(outsideCap: v)),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(c, f.copyWith(period: 'all', from: () => null, to: () => null, paymentType: () => null, outsideCap: false)), style: OutlinedButton.styleFrom(foregroundColor: Brand.ink, side: const BorderSide(color: Brand.line), minimumSize: const Size.fromHeight(52)), child: const Text('Clear'))),
                  const SizedBox(width: 12),
                  Expanded(flex: 2, child: FilledButton(onPressed: () => Navigator.pop(c, f), child: const Text('Show entries'))),
                ]),
              ]),
            ),
          );
        },
      ),
    );
    if (picked != null && mounted) setState(() => _f = picked);
  }

  /// One line that says which sheet filters are on, so a short list is never a mystery.
  String _extraLabel() {
    final parts = <String>[
      if (_f.period == 'custom' && _f.from != null && _f.to != null) '${shortDate(_f.from!)} to ${shortDate(_f.to!)}' else if (_f.period != 'all') _periods[_f.period]!,
      if (_f.paymentType != null) _payments[_f.paymentType]!,
      if (_f.outsideCap) 'Outside the cap',
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(txnsProvider).asData?.value ?? const <Txn>[];
    final cats = ref.watch(categoriesProvider).asData?.value ?? const <Cat>[];
    final catNames = {for (final c in cats) c.id: c.name};
    final today = todayKL();
    final f = _f.copyWith(query: _search.text);

    final txns = applyFilter(all, f, today: today, categoryNames: catNames);
    final totals = totalsOf(txns);
    final shownCats = cats.where((c) => f.direction == 'all' || c.kind == f.direction).toList();

    // Rows: a header per day (with that day's spend), then its entries.
    final rows = <Object>[];
    String? current;
    for (final t in txns) {
      if (t.spentAt != current) {
        current = t.spentAt;
        final day = current;
        final spend = txns.where((x) => x.spentAt == day && x.direction == 'spend').fold<int>(0, (s, x) => s + x.amountCents);
        rows.add((label: _dayLabel(day, today), spend: spend));
      }
      rows.add(t);
    }

    return SafeArea(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(padding: EdgeInsets.fromLTRB(20, 24, 20, 8), child: Text('Activity', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.8))),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search shop, note or category',
                  prefixIcon: const Icon(Icons.search, size: 22),
                  suffixIcon: f.query.trim().isEmpty ? null : IconButton(icon: const Icon(Icons.close, size: 20), tooltip: 'Clear', onPressed: () => setState(_search.clear)),
                ),
              ),
            ),
            IconButton(
              icon: Badge(isLabelVisible: _f.hasExtra, backgroundColor: Brand.amber, smallSize: 9, child: const Icon(Icons.tune)),
              tooltip: 'Filters: when, paid with, outside the cap',
              onPressed: _openFilters,
            ),
          ]),
        ),
        SizedBox(
          height: 44,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 20), children: [
            for (final e in const {'all': 'All', 'spend': 'Spent', 'income': 'Income'}.entries)
              _chip(e.value, _f.direction == e.key, () => setState(() {
                    final keepCat = _f.categoryId == null || e.key == 'all' || cats.where((c) => c.id == _f.categoryId).firstOrNull?.kind == e.key;
                    _f = _f.copyWith(direction: e.key, categoryId: keepCat ? null : () => null);
                  })),
            const SizedBox(width: 6),
            for (final c in shownCats) _chip(c.name, _f.categoryId == c.id, () => setState(() => _f = _f.copyWith(categoryId: () => _f.categoryId == c.id ? null : c.id)), outline: true),
          ]),
        ),
        if (f.isActive)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (_f.hasExtra) Text(_extraLabel(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Brand.forest)),
              Text(
                [
                  '${totals.count} ${totals.count == 1 ? 'entry' : 'entries'}',
                  if (totals.spentCents > 0) 'spent ${rm(totals.spentCents)}',
                  if (totals.incomeCents > 0) 'in ${rm(totals.incomeCents)}',
                ].join(' · '),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ]),
          ),
        Expanded(
          child: rows.isEmpty
              ? Center(child: Text(f.isActive ? 'Nothing matches.' : 'No entries yet.', style: const TextStyle(color: Brand.muted)))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                  itemCount: rows.length,
                  itemBuilder: (context, i) {
                    final r = rows[i];
                    if (r is Txn) return _row(context, r);
                    final h = r as ({String label, int spend});
                    return Padding(
                      padding: const EdgeInsets.only(top: 14, bottom: 4),
                      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Text(h.label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Brand.muted)),
                        if (h.spend > 0) Text(rm(h.spend), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Brand.muted)),
                      ]),
                    );
                  },
                ),
        ),
      ]),
    );
  }

  Widget _chip(String label, bool on, VoidCallback onTap, {bool outline = false}) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: on,
          showCheckmark: false,
          onSelected: (_) => onTap(),
          selectedColor: Brand.forest,
          backgroundColor: outline ? Colors.transparent : Brand.card,
          side: const BorderSide(color: Brand.line),
          labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: on ? Brand.paper : Brand.ink),
        ),
      );

  Widget _row(BuildContext context, Txn t) {
    return Dismissible(
      key: ValueKey(t.id),
      direction: DismissDirection.endToStart,
      background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), color: Brand.danger, child: const Icon(Icons.delete_outline, color: Colors.white)),
      onDismissed: (_) {
        final db = ref.read(dbProvider);
        final ledger = ref.read(ledgerProvider.notifier);
        final removed = ledger.removeForTxn(t.id); // what friends owe for this receipt goes with it
        db.softDelete(t.id).then((_) => ref.read(syncProvider.notifier).run());
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(
            content: Text('Deleted ${t.merchant}'),
            action: SnackBarAction(
                label: 'Undo',
                textColor: Brand.amber,
                onPressed: () async {
                  final snap = await removed;
                  if (snap != null) await ledger.restoreSnapshot(snap);
                  await db.restore(t.id);
                  ref.read(syncProvider.notifier).run();
                }),
          ));
      },
      child: TxnTile(txn: t),
    );
  }
}

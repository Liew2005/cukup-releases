import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import '../core/time.dart';
import '../data/db.dart';
import '../data/ledger.dart';
import '../data/providers.dart';
import '../theme/theme.dart';
import 'widgets.dart';

class ActivityPage extends ConsumerStatefulWidget {
  const ActivityPage({super.key});
  @override
  ConsumerState<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends ConsumerState<ActivityPage> {
  final _search = TextEditingController();
  String _direction = 'all'; // all | spend | income
  int? _categoryId;

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

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(txnsProvider).asData?.value ?? const <Txn>[];
    final cats = ref.watch(categoriesProvider).asData?.value ?? const <Cat>[];
    final catNames = {for (final c in cats) c.id: c.name};
    final q = _search.text.trim().toLowerCase();
    final today = todayKL();

    final txns = all.where((t) {
      if (_direction != 'all' && t.direction != _direction) return false;
      if (_categoryId != null && t.categoryId != _categoryId) return false;
      if (q.isNotEmpty && !('${t.merchant} ${t.note ?? ''} ${catNames[t.categoryId] ?? ''}'.toLowerCase().contains(q))) return false;
      return true;
    }).toList();

    final shownCats = cats.where((c) => _direction == 'all' || c.kind == _direction).toList();
    final filtering = q.isNotEmpty || _direction != 'all' || _categoryId != null;

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
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search shop, note or category',
              prefixIcon: const Icon(Icons.search, size: 22),
              suffixIcon: q.isEmpty ? null : IconButton(icon: const Icon(Icons.close, size: 20), tooltip: 'Clear', onPressed: () => setState(_search.clear)),
            ),
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 20), children: [
            for (final e in const {'all': 'All', 'spend': 'Spent', 'income': 'Income'}.entries)
              _chip(e.value, _direction == e.key, () => setState(() {
                    _direction = e.key;
                    if (_categoryId != null && e.key != 'all' && cats.where((c) => c.id == _categoryId).firstOrNull?.kind != e.key) _categoryId = null;
                  })),
            const SizedBox(width: 6),
            for (final c in shownCats) _chip(c.name, _categoryId == c.id, () => setState(() => _categoryId = _categoryId == c.id ? null : c.id), outline: true),
          ]),
        ),
        Expanded(
          child: rows.isEmpty
              ? Center(child: Text(filtering ? 'Nothing matches.' : 'No entries yet.', style: const TextStyle(color: Brand.muted)))
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

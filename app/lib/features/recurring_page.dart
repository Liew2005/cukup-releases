import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../core/format.dart';
import '../core/recurring.dart';
import '../core/time.dart';
import '../data/db.dart';
import '../data/providers.dart';
import '../data/recurring_poster.dart';
import '../theme/theme.dart';
import 'chips.dart';

const _payments = {'cash': 'Cash', 'debit': 'Debit', 'ewallet': 'E-wallet', 'credit_card': 'Credit card', 'spaylater': 'SPayLater'};

String _ordinal(int n) => '$n${n % 10 == 1 && n != 11 ? 'st' : n % 10 == 2 && n != 12 ? 'nd' : n % 10 == 3 && n != 13 ? 'rd' : 'th'}';

/// Rent, salary, subscriptions: entries that add themselves on the same day every month.
class RecurringPage extends ConsumerWidget {
  const RecurringPage({super.key});

  Future<void> _edit(BuildContext context, {RecurringItem? item}) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Brand.paper,
        showDragHandle: true,
        builder: (_) => _RecurringForm(item: item),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(recurringProvider).asData?.value ?? const <RecurringItem>[];
    final cats = ref.watch(categoriesProvider).asData?.value ?? const <Cat>[];
    final names = {for (final c in cats) c.id: c.name};

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), tooltip: 'Back', onPressed: () => context.pop()),
        title: const Text('Repeating entries', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [IconButton(icon: const Icon(Icons.add), tooltip: 'Add', onPressed: () => _edit(context))],
      ),
      body: SafeArea(
        child: items.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Nothing repeating yet. Add rent, a salary or a subscription and it will log itself on the day, even if you do not open the app.', style: TextStyle(color: Brand.muted, fontSize: 15)),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                children: [
                  for (final r in items)
                    InkWell(
                      onTap: () => _edit(context, item: r),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: const BoxDecoration(border: Border(top: BorderSide(color: Brand.line))),
                        child: Row(children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(r.title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: r.active ? Brand.ink : Brand.muted)),
                              const SizedBox(height: 2),
                              Text('${r.direction == 'income' ? 'Income' : 'Spend'} · every ${_ordinal(r.dayOfMonth)} · ${names[r.categoryId] ?? ''}', style: const TextStyle(fontSize: 13, color: Brand.muted)),
                            ]),
                          ),
                          Text(rm(r.amountCents), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: r.active ? Brand.ink : Brand.muted)),
                          Switch(
                            value: r.active,
                            activeThumbColor: Brand.paper,
                            activeTrackColor: Brand.forest,
                            onChanged: (v) async {
                              await ref.read(dbProvider).saveRecurring(RecurringItemsCompanion(
                                    id: Value(r.id),
                                    title: Value(r.title),
                                    direction: Value(r.direction),
                                    amountCents: Value(r.amountCents),
                                    categoryId: Value(r.categoryId),
                                    paymentType: Value(r.paymentType),
                                    dayOfMonth: Value(r.dayOfMonth),
                                    countsTowardCap: Value(r.countsTowardCap),
                                    active: Value(v),
                                    lastPosted: Value(v ? shiftMonth(todayKL().substring(0, 7), -1) : r.lastPosted), // do not back-post months it was off
                                  ));
                              ref.read(syncProvider.notifier).run();
                            },
                          ),
                        ]),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _RecurringForm extends ConsumerStatefulWidget {
  const _RecurringForm({this.item});
  final RecurringItem? item;
  @override
  ConsumerState<_RecurringForm> createState() => _RecurringFormState();
}

class _RecurringFormState extends ConsumerState<_RecurringForm> {
  late final _title = TextEditingController(text: widget.item?.title ?? '');
  late final _amount = TextEditingController(text: widget.item == null ? '' : (widget.item!.amountCents / 100).toStringAsFixed(2));
  late String _direction = widget.item?.direction ?? 'spend';
  late String _payment = widget.item?.paymentType ?? 'debit';
  late int _day = widget.item?.dayOfMonth ?? 1;
  late bool _counts = widget.item?.countsTowardCap ?? false;
  late int? _categoryId = widget.item?.categoryId;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save(List<Cat> cats) async {
    final cents = parseCents(_amount.text);
    final title = _title.text.trim();
    final catId = _categoryId != null && cats.any((c) => c.id == _categoryId && c.kind == _direction) ? _categoryId : cats.where((c) => c.kind == _direction).firstOrNull?.id;
    if (title.isEmpty) return setState(() => _error = 'Give it a name, like Rent.');
    if (cents == null || cents <= 0) return setState(() => _error = 'Enter the amount, like 800.00.');
    if (catId == null) return setState(() => _error = 'Categories have not loaded yet. Open Home once while online.');
    final old = widget.item;
    final isNew = old == null;
    await ref.read(dbProvider).saveRecurring(RecurringItemsCompanion(
          id: Value(old?.id ?? const Uuid().v4()),
          title: Value(title),
          direction: Value(_direction),
          amountCents: Value(cents),
          categoryId: Value(catId),
          paymentType: Value(_direction == 'income' ? 'debit' : _payment),
          dayOfMonth: Value(_day),
          countsTowardCap: Value(_direction == 'spend' && _payment != 'spaylater' && _counts),
          active: Value(old?.active ?? true),
          // A new item starts from last month, so this month's entry posts right away if its day has passed.
          lastPosted: Value(isNew ? shiftMonth(todayKL().substring(0, 7), -1) : old.lastPosted),
        ));
    await postDueRecurring(ref.read(dbProvider));
    ref.read(syncProvider.notifier).run();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    await ref.read(dbProvider).deleteRecurring(widget.item!.id);
    ref.read(syncProvider.notifier).run();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cats = ref.watch(categoriesProvider).asData?.value ?? const <Cat>[];
    final kindCats = {for (final c in cats.where((c) => c.kind == _direction)) c.id: c.name};
    final selected = _categoryId != null && kindCats.containsKey(_categoryId) ? _categoryId : kindCats.keys.firstOrNull;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.item == null ? 'Add repeating entry' : 'Edit repeating entry', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          SegmentedButton<String>(
            segments: const [ButtonSegment(value: 'spend', label: Text('Spent')), ButtonSegment(value: 'income', label: Text('Income'))],
            selected: {_direction},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() {
              _direction = s.first;
              _categoryId = null;
            }),
            style: SegmentedButton.styleFrom(selectedBackgroundColor: Brand.forest, selectedForegroundColor: Brand.paper, minimumSize: const Size.fromHeight(40)),
          ),
          const SizedBox(height: 12),
          TextField(controller: _title, textCapitalization: TextCapitalization.words, decoration: InputDecoration(labelText: _direction == 'spend' ? 'Name (like Rent)' : 'Name (like Salary)')),
          const SizedBox(height: 12),
          TextField(controller: _amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Amount', prefixText: 'RM ')),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _day,
            decoration: const InputDecoration(labelText: 'Posts on day'),
            items: [for (var d = 1; d <= 28; d++) DropdownMenuItem(value: d, child: Text('Every ${_ordinal(d)}'))],
            onChanged: (v) => setState(() => _day = v ?? 1),
          ),
          const SizedBox(height: 14),
          const FieldLabel('Category'),
          PickChips<int>(options: kindCats, selected: selected, onSelected: (id) => setState(() => _categoryId = id)),
          if (_direction == 'spend') ...[
            const SizedBox(height: 14),
            const FieldLabel('Paid with'),
            PickChips<String>(options: _payments, selected: _payment, onSelected: (p) => setState(() => _payment = p)),
            if (_payment != 'spaylater')
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Count toward weekly cap'),
                subtitle: const Text('Leave off for rent and fixed bills', style: TextStyle(fontSize: 12, color: Brand.muted)),
                value: _counts,
                activeThumbColor: Brand.paper,
                activeTrackColor: Brand.forest,
                onChanged: (v) => setState(() => _counts = v),
              ),
          ] else
            const Padding(padding: EdgeInsets.only(top: 8), child: Text('Income never changes your weekly cap.', style: TextStyle(fontSize: 13, color: Brand.muted))),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: Brand.danger, fontWeight: FontWeight.w600))),
          const SizedBox(height: 16),
          FilledButton(onPressed: () => _save(cats), child: Text(widget.item == null ? 'Save' : 'Save changes')),
          if (widget.item != null) Center(child: TextButton(onPressed: _delete, child: const Text('Delete (past entries stay)', style: TextStyle(color: Brand.danger, fontWeight: FontWeight.w600)))),
        ]),
      ),
    );
  }
}

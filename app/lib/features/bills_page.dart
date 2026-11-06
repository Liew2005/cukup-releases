import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/format.dart';
import '../core/time.dart';
import '../data/db.dart';
import '../data/providers.dart';
import '../theme/theme.dart';
import 'chips.dart';
import 'sweep_cards.dart';

const _kinds = {'spaylater': 'SPayLater', 'credit_card': 'Credit card', 'rent': 'Rent', 'utilities': 'Utilities', 'other': 'Other'};

/// SPayLater (and other) bills. Purchases made on SPayLater in a month fall due on the 1st of the next month.
class BillsPage extends ConsumerWidget {
  const BillsPage({super.key});

  Future<void> _togglePaid(BuildContext context, WidgetRef ref, Bill b) async {
    final db = ref.read(dbProvider);
    final paid = b.paidAt == null;
    await db.saveBill(BillsCompanion(id: Value(b.id), name: Value(b.name), kind: Value(b.kind), dueDate: Value(b.dueDate), amountCents: Value(b.amountCents), paidAt: Value(paid ? todayKL() : null)));
    ref.read(syncProvider.notifier).run();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(paid ? '${b.name} marked paid' : '${b.name} back to unpaid'),
        action: SnackBarAction(label: 'Undo', textColor: Brand.amber, onPressed: () => _togglePaid(context, ref, b.copyWith(paidAt: Value(paid ? todayKL() : null)))),
      ));
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, {Bill? bill, int? amount, String? due, String? name}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Brand.paper,
      showDragHandle: true,
      builder: (_) => _BillForm(bill: bill, amount: amount, due: due, name: name),
    );
  }

  String _dueText(int days) {
    if (days < 0) return 'Overdue by ${-days} ${days == -1 ? 'day' : 'days'}';
    if (days == 0) return 'Due today';
    if (days == 1) return 'Due tomorrow';
    return 'Due in $days days';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bills = ref.watch(billsProvider).asData?.value ?? const <Bill>[];
    final today = todayKL();
    final monthSpay = ref.watch(spaylaterMonthProvider(firstOfMonth(today))).asData?.value ?? 0;
    final due = nextFirst(today);
    final upcoming = bills.where((b) => b.paidAt == null).toList();
    final paid = bills.where((b) => b.paidAt != null).toList()..sort((a, b) => b.paidAt!.compareTo(a.paidAt!));
    final alreadyBilled = upcoming.any((b) => b.kind == 'spaylater' && b.dueDate == due);
    final unpaidTotal = upcoming.fold<int>(0, (s, b) => s + b.amountCents);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Bills', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.8)),
            TextButton.icon(onPressed: () => _edit(context, ref), icon: const Icon(Icons.add, size: 18), label: const Text('Add bill'), style: TextButton.styleFrom(foregroundColor: Brand.forest)),
          ]),
          if (upcoming.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('${rm(unpaidTotal)} still to pay', style: const TextStyle(fontSize: 15, color: Brand.muted))),
          const SizedBox(height: 10),
          const GoalCard(),
          if (monthSpay > 0)
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: Brand.mint, borderRadius: BorderRadius.circular(18)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('SPayLater this month', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Brand.muted)),
                const SizedBox(height: 2),
                Text(rm(monthSpay), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.8, color: Brand.forest)),
                Text('Falls due on ${shortDate(due)}.', style: const TextStyle(fontSize: 13, color: Brand.muted)),
                if (!alreadyBilled)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(42)),
                      onPressed: () => _edit(context, ref, amount: monthSpay, due: due, name: 'SPayLater ${shortDate(due)}'),
                      child: const Text('Add as a bill'),
                    ),
                  ),
              ]),
            ),
          if (upcoming.isEmpty && paid.isEmpty)
            const Padding(padding: EdgeInsets.symmetric(vertical: 30), child: Text('No bills yet. Add one and Cukup will remind you 3 days and 1 day before, and on the day.', style: TextStyle(color: Brand.muted))),
          if (upcoming.isNotEmpty) const Padding(padding: EdgeInsets.only(top: 6, bottom: 4), child: Text('Upcoming', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
          for (final b in upcoming)
            _row(
              context,
              ref,
              b,
              sub: _dueText(daysBetween(today, b.dueDate)),
              subColor: daysBetween(today, b.dueDate) < 0 ? Brand.danger : (daysBetween(today, b.dueDate) <= 3 ? const Color(0xFF9A6A00) : Brand.muted),
              action: FilledButton.tonal(
                onPressed: () => _togglePaid(context, ref, b),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 14), backgroundColor: Brand.mint, foregroundColor: Brand.forest),
                child: const Text('Mark paid', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          if (paid.isNotEmpty) const Padding(padding: EdgeInsets.only(top: 22, bottom: 4), child: Text('Paid', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
          for (final b in paid.take(8))
            _row(
              context,
              ref,
              b,
              sub: 'Paid ${shortDate(b.paidAt!.substring(0, 10))}',
              subColor: Brand.muted,
              action: TextButton(onPressed: () => _togglePaid(context, ref, b), child: const Text('Undo', style: TextStyle(color: Brand.muted))),
              dim: true,
            ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, WidgetRef ref, Bill b, {required String sub, required Color subColor, required Widget action, bool dim = false}) {
    return InkWell(
      onTap: () => _edit(context, ref, bill: b),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: Brand.line))),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(b.name, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: dim ? Brand.muted : Brand.ink)),
              const SizedBox(height: 2),
              Text('${_kinds[b.kind] ?? b.kind} · ${shortDate(b.dueDate)} · $sub', style: TextStyle(fontSize: 13, color: subColor, fontWeight: FontWeight.w600)),
            ]),
          ),
          Text(rm(b.amountCents), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: dim ? Brand.muted : Brand.ink)),
          const SizedBox(width: 10),
          action,
        ]),
      ),
    );
  }
}

class _BillForm extends ConsumerStatefulWidget {
  const _BillForm({this.bill, this.amount, this.due, this.name});
  final Bill? bill;
  final int? amount;
  final String? due;
  final String? name;
  @override
  ConsumerState<_BillForm> createState() => _BillFormState();
}

class _BillFormState extends ConsumerState<_BillForm> {
  late final _name = TextEditingController(text: widget.bill?.name ?? widget.name ?? '');
  late final _amount = TextEditingController(text: (widget.bill?.amountCents ?? widget.amount) == null ? '' : ((widget.bill?.amountCents ?? widget.amount)! / 100).toStringAsFixed(2));
  late String _kind = widget.bill?.kind ?? 'spaylater';
  late String _due = widget.bill?.dueDate ?? widget.due ?? nextFirst(todayKL());
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = parseYmd(todayKL());
    final picked = await showDatePicker(
      context: context,
      initialDate: parseYmd(_due),
      firstDate: DateTime.utc(now.year - 1),
      lastDate: DateTime.utc(now.year + 2),
      builder: (context, child) => Theme(data: Theme.of(context).copyWith(colorScheme: Theme.of(context).colorScheme.copyWith(primary: Brand.forest)), child: child!),
    );
    if (picked != null) setState(() => _due = ymd(picked));
  }

  Future<void> _save() async {
    final cents = parseCents(_amount.text);
    final name = _name.text.trim();
    if (name.isEmpty) return setState(() => _error = 'Give the bill a name.');
    if (cents == null || cents <= 0) return setState(() => _error = 'Enter the amount, like 120.50.');
    await ref.read(dbProvider).saveBill(BillsCompanion(
          id: Value(widget.bill?.id ?? const Uuid().v4()),
          name: Value(name),
          kind: Value(_kind),
          dueDate: Value(_due),
          amountCents: Value(cents),
          paidAt: Value(widget.bill?.paidAt),
        ));
    ref.read(syncProvider.notifier).run();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    await ref.read(dbProvider).deleteBill(widget.bill!.id);
    ref.read(syncProvider.notifier).run();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.bill == null ? 'Add bill' : 'Edit bill', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Name')),
          const SizedBox(height: 12),
          TextField(controller: _amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Amount', prefixText: 'RM ')),
          const SizedBox(height: 12),
          InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(14),
            child: InputDecorator(decoration: const InputDecoration(labelText: 'Due date', suffixIcon: Icon(Icons.calendar_today_outlined, size: 20)), child: Text(shortDate(_due), style: const TextStyle(fontSize: 16))),
          ),
          const SizedBox(height: 14),
          const FieldLabel('Type'),
          PickChips<String>(options: _kinds, selected: _kind, onSelected: (k) => setState(() => _kind = k)),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: Brand.danger, fontWeight: FontWeight.w600))),
          const SizedBox(height: 18),
          FilledButton(onPressed: _save, child: Text(widget.bill == null ? 'Save bill' : 'Save changes')),
          if (widget.bill != null) Center(child: TextButton(onPressed: _delete, child: const Text('Delete bill', style: TextStyle(color: Brand.danger, fontWeight: FontWeight.w600)))),
        ]),
      ),
    );
  }
}

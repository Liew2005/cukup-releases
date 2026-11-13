import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../core/format.dart';
import '../core/time.dart';
import '../data/db.dart';
import '../data/providers.dart';
import '../theme/theme.dart';
import 'cap_switch.dart';
import 'chips.dart';
import 'dup_dialog.dart';

const _payments = {'cash': 'Cash', 'debit': 'Debit', 'ewallet': 'E-wallet', 'credit_card': 'Credit card', 'spaylater': 'SPayLater'};

/// Add an entry by hand, or edit an existing one without items (pass [editId]).
class AddPage extends ConsumerStatefulWidget {
  const AddPage({super.key, this.editId});
  final String? editId;
  @override
  ConsumerState<AddPage> createState() => _AddPageState();
}

class _AddPageState extends ConsumerState<AddPage> {
  final _amount = TextEditingController();
  final _name = TextEditingController();
  final _note = TextEditingController();
  Txn? _existing;
  String _direction = 'spend';
  String _payment = 'ewallet';
  int? _categoryId;
  bool? _capOverride; // null follows the category: Bills stays out of the cap
  String _date = todayKL();
  String? _error;
  bool _saving = false;
  bool _loading = false;
  bool _categoryTouched = false;

  /// Typing a shop you have used before picks the category you chose last time.
  Future<void> _applyRule(String merchant) async {
    if (_categoryTouched || _direction != 'spend') return;
    final id = await ref.read(dbProvider).getRule(merchant);
    if (id != null && mounted && !_categoryTouched && id != _categoryId) setState(() => _categoryId = id);
  }

  @override
  void initState() {
    super.initState();
    if (widget.editId != null) {
      _loading = true;
      _load();
    }
  }

  Future<void> _load() async {
    final t = await ref.read(dbProvider).getTxn(widget.editId!);
    if (t != null) {
      _existing = t;
      _amount.text = (t.amountCents / 100).toStringAsFixed(2);
      _name.text = t.merchant;
      _note.text = t.note ?? '';
      _direction = t.direction;
      _payment = t.paymentType;
      _categoryId = t.categoryId;
      _capOverride = t.paymentType == 'spaylater' ? null : t.countsTowardCap;
      _date = t.spentAt;
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _amount.dispose();
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = parseYmd(todayKL());
    final picked = await showDatePicker(
      context: context,
      initialDate: parseYmd(_date).isAfter(now) ? now : parseYmd(_date),
      firstDate: DateTime.utc(now.year - 2),
      lastDate: now,
      builder: (context, child) => Theme(data: Theme.of(context).copyWith(colorScheme: Theme.of(context).colorScheme.copyWith(primary: Brand.forest)), child: child!),
    );
    if (picked != null) setState(() => _date = ymd(picked));
  }

  Future<void> _save(List<Cat> cats) async {
    final cents = parseCents(_amount.text);
    final name = _name.text.trim();
    final catId = _categoryId ?? cats.where((c) => c.kind == _direction).firstOrNull?.id;
    String? err;
    if (cents == null || cents <= 0) {
      err = 'Enter an amount above zero, like 12.50.';
    } else if (cents > 100000000) {
      err = 'That amount is too large.';
    } else if (name.isEmpty) {
      err = _direction == 'spend' ? 'Where did you spend it?' : 'Where did it come from?';
    } else if (catId == null) {
      err = 'Categories have not loaded yet. Open Home once while online.';
    }
    if (err != null) {
      setState(() => _error = err);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    final income = _direction == 'income';
    final payment = income ? 'debit' : _payment;
    if (widget.editId == null && !await confirmNotDuplicate(context, ref, merchant: name, amountCents: cents!, date: _date, direction: _direction)) {
      if (mounted) setState(() => _saving = false);
      return;
    }
    final now = nowIso();
    final old = _existing;
    final note = _note.text.trim();
    await ref.read(dbProvider).saveTxn(
          TxnsCompanion.insert(
            id: old?.id ?? const Uuid().v4(),
            spentAt: _date,
            merchant: name,
            amountCents: cents!,
            categoryId: catId!,
            paymentType: payment,
            createdAt: old?.createdAt ?? now,
            updatedAt: now,
            receiptTotalCents: Value(old?.receiptTotalCents),
            taxCents: Value(old?.taxCents ?? 0),
            direction: Value(_direction),
            countsTowardCap: Value(!income && payment != 'spaylater' && (_capOverride ?? capDefault(cats.where((c) => c.id == catId).firstOrNull?.name))),
            note: Value(note.isEmpty ? null : note),
            source: Value(old?.source ?? 'manual'),
            reference: Value(old?.reference),
            confidence: Value(old?.confidence),
          ),
          const [],
        );
    if (!income) await ref.read(dbProvider).learnRule(name, catId);
    ref.read(syncProvider.notifier).run();
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final cats = ref.watch(categoriesProvider).asData?.value ?? const <Cat>[];
    final kindCats = {for (final c in cats.where((c) => c.kind == _direction)) c.id: c.name};
    final selected = _categoryId != null && kindCats.containsKey(_categoryId) ? _categoryId : kindCats.keys.firstOrNull;
    final editing = widget.editId != null;

    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator(color: Brand.forest)));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close), tooltip: 'Close', onPressed: () => context.pop()),
        title: Text(editing ? 'Edit entry' : 'Add entry', style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            SegmentedButton<String>(
              segments: const [ButtonSegment(value: 'spend', label: Text('Spent')), ButtonSegment(value: 'income', label: Text('Income'))],
              selected: {_direction},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() {
                _direction = s.first;
                _categoryId = null;
              }),
              style: SegmentedButton.styleFrom(selectedBackgroundColor: Brand.forest, selectedForegroundColor: Brand.paper, minimumSize: const Size.fromHeight(44)),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _amount,
              autofocus: !editing,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800),
              decoration: const InputDecoration(labelText: 'Amount', prefixText: 'RM '),
            ),
            const SizedBox(height: 14),
            TextField(controller: _name, onChanged: _applyRule, textCapitalization: TextCapitalization.words, decoration: InputDecoration(labelText: _direction == 'spend' ? 'Where' : 'From')),
            const SizedBox(height: 18),
            const FieldLabel('Category'),
            PickChips<int>(options: kindCats, selected: selected, onSelected: (id) => setState(() {
              _categoryId = id;
              _categoryTouched = true;
            })),
            if (_direction == 'spend') ...[
              const SizedBox(height: 18),
              const FieldLabel('Paid with'),
              PickChips<String>(options: _payments, selected: _payment, onSelected: (p) => setState(() => _payment = p)),
              if (_payment == 'spaylater')
                const Padding(padding: EdgeInsets.only(top: 8), child: Text('Stays out of your weekly cap. You pay it back through the SPayLater schedule.', style: TextStyle(fontSize: 13, color: Brand.muted))),
                if (_payment != 'spaylater') CapSwitch(value: _capOverride ?? capDefault(kindCats[selected]), onChanged: (v) => setState(() => _capOverride = v)),
            ] else
              const Padding(padding: EdgeInsets.only(top: 10), child: Text('Income never changes your weekly cap.', style: TextStyle(fontSize: 13, color: Brand.muted))),
            const SizedBox(height: 18),
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(14),
              child: InputDecorator(decoration: const InputDecoration(labelText: 'Date', suffixIcon: Icon(Icons.calendar_today_outlined, size: 20)), child: Text(_date == todayKL() ? 'Today · ${shortDate(_date)}' : shortDate(_date), style: const TextStyle(fontSize: 16))),
            ),
            const SizedBox(height: 14),
            TextField(controller: _note, decoration: const InputDecoration(labelText: 'Note (optional)')),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 14), child: Text(_error!, style: const TextStyle(color: Brand.danger, fontWeight: FontWeight.w600))),
            const SizedBox(height: 22),
            FilledButton(onPressed: _saving ? null : () => _save(cats), child: Text(editing ? 'Save changes' : 'Save')),
          ],
        ),
      ),
    );
  }
}

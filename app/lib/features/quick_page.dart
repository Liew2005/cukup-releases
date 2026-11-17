import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../core/format.dart';
import '../core/ledger.dart';
import '../core/split_bill.dart';
import '../core/quick.dart' show applyKey;
import '../data/ledger.dart';
import 'friend_picker.dart';
import '../core/time.dart';
import '../data/db.dart';
import '../data/providers.dart';
import '../theme/theme.dart';
import 'cap_switch.dart';
import 'chips.dart';
import 'dup_dialog.dart';

/// Fast spending entry: type where, key in the amount, save.
class QuickPage extends ConsumerStatefulWidget {
  const QuickPage({super.key});
  @override
  ConsumerState<QuickPage> createState() => _QuickPageState();
}

class _QuickPageState extends ConsumerState<QuickPage> {
  String _amount = '';
  final _name = TextEditingController();
  int? _catId; // chosen category; follows the shop's learned category until you tap one yourself
  bool _catManual = false;
  bool? _capOverride; // null follows the category: Bills stays out of the cap
  Set<String> _friends = {}; // friends sharing this bill; empty means it is all yours
  bool _treat = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }


  /// Typing a shop you have used before suggests its usual category.
  Future<void> _nameChanged(String v) async {
    if (_catManual || v.trim().isEmpty) return;
    final learned = await ref.read(dbProvider).getRule(v.trim());
    if (learned != null && mounted && !_catManual && _name.text == v) setState(() => _catId = learned);
  }

  /// Even split of the bill: you and the friends who came. A treat puts it all on you.
  Map<String, int> _split(int cents) => _friends.isEmpty ? {me: cents} : splitTotals([Slot(cents, {me, ..._friends}, treat: _treat)], cents);

  Future<void> _save(List<Cat> cats) async {
    final bill = parseCents(_amount);
    final cents = bill == null ? null : (_split(bill)[me] ?? 0); // only your share is your spending
    final name = _name.text.trim();
    if (cents == null || cents <= 0) return setState(() => _error = 'Key in an amount first.');
    if (name.isEmpty) return setState(() => _error = 'Where did you spend it?');
    final db = ref.read(dbProvider);
    final spendCats = cats.where((c) => c.kind == 'spend');
    var catId = _catId ?? await db.getRule(name);
    catId ??= spendCats.firstOrNull?.id;
    if (catId == null) return setState(() => _error = 'Categories have not loaded yet. Open Home once while online.');
    const payment = 'ewallet'; // More options has the full form with payment type, date and note
    setState(() {
      _saving = true;
      _error = null;
    });
    if (!mounted) return;
    if (!await confirmNotDuplicate(context, ref, merchant: name, amountCents: cents, date: todayKL())) {
      if (mounted) setState(() => _saving = false);
      return;
    }
    final now = nowIso();
    final txnId = const Uuid().v4();
    await db.saveTxn(
      TxnsCompanion.insert(
        id: txnId,
        spentAt: todayKL(),
        merchant: name,
        amountCents: cents,
        categoryId: catId,
        paymentType: payment,
        createdAt: now,
        updatedAt: now,
        direction: const Value('spend'),
        countsTowardCap: Value(_capOverride ?? capDefault(cats.where((c) => c.id == catId).firstOrNull?.name)),
        source: const Value('quick'),
      ),
      const [],
    );
    await db.learnRule(name, catId);
    if (_friends.isNotEmpty) {
      final split = _split(bill!);
      await ref.read(ledgerProvider.notifier).addDebts([
        for (final f in _friends)
          if ((split[f] ?? 0) > 0) Debt(id: const Uuid().v4(), friendId: f, date: todayKL(), title: name, cents: split[f]!, items: const ['even split'], txnId: txnId),
      ]);
    }
    ref.read(syncProvider.notifier).run();
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final cats = ref.watch(categoriesProvider).asData?.value ?? const <Cat>[];
    final cents = parseCents(_amount);
    final spendCats = cats.where((c) => c.kind == 'spend').toList();
    final selectedCat = _catId ?? spendCats.firstOrNull?.id;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close), tooltip: 'Close', onPressed: () => context.pop()),
        title: const Text('Quick add', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [TextButton(onPressed: () => context.pushReplacement('/add'), child: const Text('More options', style: TextStyle(color: Brand.forest, fontWeight: FontWeight.w600)))],
      ),
      body: SafeArea(
        child: Column(children: [
          // The form: scrolls when there are many categories or friends.
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                TextField(controller: _name, textCapitalization: TextCapitalization.words, onChanged: _nameChanged, decoration: const InputDecoration(labelText: 'Where')),
                const SizedBox(height: 16),
                const FieldLabel('Category'),
                PickChips<int>(
                  options: {for (final c in spendCats) c.id: c.name},
                  selected: selectedCat,
                  onSelected: (id) => setState(() {
                    _catId = id;
                    _catManual = true;
                  }),
                ),
                const SizedBox(height: 8),
                CapSwitch(value: _capOverride ?? capDefault(spendCats.where((c) => c.id == selectedCat).firstOrNull?.name), onChanged: (v) => setState(() => _capOverride = v)),
                const FieldLabel('Split evenly with'),
                FriendChips(selected: _friends, onChanged: (s) => setState(() => _friends = s)),
                if (_friends.isNotEmpty)
                  Row(children: [
                    Expanded(child: Text(cents == null || cents <= 0 ? 'Key in the bill to see the split.' : 'You pay ${rm(_split(cents)[me] ?? 0)}, they owe ${rm(cents - (_split(cents)[me] ?? 0))} in total', style: const TextStyle(fontSize: 13, color: Brand.muted))),
                    const Text('Treat', style: TextStyle(fontWeight: FontWeight.w600)),
                    Switch(value: _treat, activeThumbColor: Brand.paper, activeTrackColor: Brand.forest, onChanged: (v) => setState(() => _treat = v)),
                  ]),
              ]),
            ),
          ),
          // Always on screen: the amount, the keypad and Save.
          Container(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: Brand.line))),
            child: Column(children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(_amount.isEmpty ? 'RM 0' : 'RM $_amount', style: TextStyle(fontSize: 44, fontWeight: FontWeight.w800, letterSpacing: -1.6, color: _amount.isEmpty ? Brand.muted : Brand.forest)),
              ),
              if (_error != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(_error!, style: const TextStyle(color: Brand.danger, fontWeight: FontWeight.w600))),
              const SizedBox(height: 4),
              _Keypad(onKey: (k) => setState(() {
                _amount = applyKey(_amount, k);
                _error = null;
              })),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(onPressed: _saving || cents == null || cents <= 0 ? null : () => _save(cats), child: const Text('Save')),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
class _Keypad extends StatelessWidget {
  const _Keypad({required this.onKey});
  final void Function(String) onKey;

  @override
  Widget build(BuildContext context) {
    const rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['.', '0', 'back'],
    ];
    return Column(children: [
      for (final row in rows)
        Row(children: [
          for (final k in row)
            Expanded(
              child: SizedBox(
                height: 52,
                child: TextButton(
                  onPressed: () => onKey(k),
                  child: k == 'back' ? const Icon(Icons.backspace_outlined, color: Brand.ink) : Text(k, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Brand.ink)),
                ),
              ),
            ),
        ]),
    ]);
  }
}

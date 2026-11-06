import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../core/format.dart';
import '../core/ledger.dart';
import '../core/split_bill.dart';
import '../core/time.dart';
import '../data/db.dart';
import '../data/ledger.dart';
import '../data/providers.dart';
import '../data/receipt_models.dart';
import '../theme/theme.dart';
import 'chips.dart';
import 'dup_dialog.dart';
import 'friend_picker.dart';

const _payments = {'cash': 'Cash', 'debit': 'Debit', 'ewallet': 'E-wallet', 'credit_card': 'Credit card', 'spaylater': 'SPayLater'};

/// One receipt row: [qty] x [unit] cents. Each unit has a set of people who had it:
/// [me] for yourself plus friend ids; an empty set means it is not yours and nobody owes it (someone else's order).
class _Line {
  _Line(this.id, this.name, this.qty, this.unit, int mine)
      : people = [for (var i = 0; i < qty; i++) i < mine ? {me} : <String>{}],
        treat = List<bool>.filled(qty, false);
  final String id;
  String name;
  int qty;
  int unit;
  List<Set<String>> people;
  List<bool> treat;
  int get total => qty * unit;

  /// How many units are yours.
  int get mine => people.where((p) => p.contains(me)).length;

  /// Without friends: exactly [k] units are yours, the rest are not.
  void setMine(int k) {
    people = [for (var i = 0; i < qty; i++) i < k ? {me} : <String>{}];
    treat = List<bool>.filled(qty, false);
  }

  /// Quantity changed: keep what was set, new units start as yours (or not, if none were yours).
  void resize(int newQty, {required bool fillMine}) {
    final p = [...people];
    final t = [...treat];
    while (p.length < newQty) {
      p.add(fillMine ? {me} : <String>{});
      t.add(false);
    }
    qty = newQty;
    people = p.sublist(0, newQty);
    treat = t.sublist(0, newQty);
  }

  void stripFriends(Set<String> keep) {
    for (var i = 0; i < people.length; i++) {
      people[i] = people[i].where((x) => x == me || keep.contains(x)).toSet();
      if (people[i].every((x) => x == me)) treat[i] = false;
    }
  }
}

typedef _Row = ({String id, String name, int price, bool included});

/// Saved rows: a row that is only partly yours is stored as two rows (yours, and the rest), so the
/// total of the rows always equals the receipt and old versions of the app still read it.
List<_Row> _expand(List<_Line> lines, String Function() newId) {
  final out = <_Row>[];
  for (final l in lines) {
    final label = l.qty > 1 ? '${l.name} x${l.qty}' : l.name;
    var mineCents = 0;
    for (var i = 0; i < l.qty; i++) {
      mineCents += slotShares(Slot(l.unit, l.people[i], treat: l.treat[i]))[me] ?? 0;
    }
    if (l.mine == 0) {
      out.add((id: l.id, name: label, price: l.total, included: false));
    } else if (mineCents == l.total) {
      out.add((id: l.id, name: label, price: l.total, included: true));
    } else {
      out.add((id: l.id, name: '$label (mine)', price: mineCents, included: true));
      out.add((id: newId(), name: '$label (others)', price: l.total - mineCents, included: false));
    }
  }
  return out;
}

/// Check what was read from a receipt, untick items that are not yours, and save your share.
/// Also used to edit a saved receipt that has items (pass [editId]).
class ReviewPage extends ConsumerStatefulWidget {
  const ReviewPage({super.key, this.parsed, this.editId});
  final ParsedReceipt? parsed;
  final String? editId;
  @override
  ConsumerState<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends ConsumerState<ReviewPage> {
  final _merchant = TextEditingController();
  final _uuid = const Uuid();
  final List<_Line> _lines = [];
  Txn? _existing;
  bool _loading = true;
  bool _saving = false;
  String _date = todayKL();
  int _total = 0;
  int _service = 0; // service charge, usually 10%
  int _sst = 0; // SST / service tax, usually 6%
  String _sstLabel = 'SST / service tax';
  int get _tax => _service + _sst;
  int? _categoryId;
  String _payment = 'ewallet';
  double? _confidence;
  String? _via;
  String? _reference;
  bool _isImport = false;
  List<String> _hints = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final p = widget.parsed;
    if (widget.editId != null) {
      final db = ref.read(dbProvider);
      final t = await db.getTxn(widget.editId!);
      final items = await db.getItems(widget.editId!);
      if (t != null) {
        _existing = t;
        _merchant.text = t.merchant;
        _date = t.spentAt;
        _sst = t.taxCents;
        _sstLabel = 'Tax and charges';
        _categoryId = t.categoryId;
        _payment = t.paymentType;
        _confidence = t.confidence;
        _lines.addAll(items.map((i) => _Line(i.id, i.name, 1, i.priceCents, i.included ? 1 : 0)));
        _total = t.receiptTotalCents ?? t.amountCents;
        final cfg = (await loadLedger(db)).splits[t.id]; // a bill shared with friends: bring back who had what
        if (cfg != null) _restoreSplit(cfg);
      }
    } else if (p != null) {
      _merchant.text = p.merchant ?? '';
      _date = p.date ?? todayKL();
      _service = p.serviceCents;
      _sst = p.sstCents;
      if (_service + _sst != p.taxCents) {
        // an older server only sent one combined figure
        _service = 0;
        _sst = p.taxCents;
        _sstLabel = 'Tax and charges';
      }
      _categoryId = p.categoryId;
      _confidence = p.confidence;
      _via = p.via;
      _reference = p.reference;
      _isImport = p.isImport;
      _hints = p.hints();
      _lines.addAll(p.items.map((i) => i.qty > 1 ? _Line(_uuid.v4(), i.name, i.qty, i.unitCents, i.qty) : _Line(_uuid.v4(), i.name, 1, i.priceCents, 1)));
      _total = p.totalCents ?? (_lines.fold<int>(0, (s, l) => s + l.total) + _tax + p.roundingCents);
    }
    if (widget.editId == null) {
      final learned = await ref.read(dbProvider).getRule(_merchant.text); // your past choice beats the guess
      if (learned != null) _categoryId = learned;
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _merchant.dispose();
    super.dispose();
  }

  List<_Row> get _rows => _expand(_lines, _uuid.v4);

  /// Friends who were at the table. Empty means it is only you, and the screen works as before.
  Set<String> _attendees = {};
  bool _treatAll = false; // no items to assign: you are paying for the friends' even shares

  List<Slot> get _slots {
    if (_lines.isEmpty) return _attendees.isEmpty ? const [] : [Slot(_total, {me, ..._attendees}, treat: _treatAll)];
    return [
      for (final l in _lines)
        for (var i = 0; i < l.qty; i++) Slot(l.unit, l.people[i], treat: l.treat[i]),
    ];
  }

  Map<String, int> get _split => splitTotals(_slots, _total);

  int get _share => _split[me] ?? 0;

  /// How this bill was divided, saved with the ledger so editing the receipt can redo what friends owe.
  Map<String, dynamic>? _splitConfig() {
    if (_attendees.isEmpty) return null;
    return {
      'att': _attendees.toList(),
      'treatAll': _treatAll,
      'lines': [
        for (final l in _lines)
          {
            'n': l.name,
            'q': l.qty,
            'u': l.unit,
            'p': [for (final s in l.people) s.toList()],
            't': l.treat,
          },
      ],
    };
  }

  void _restoreSplit(Map<String, dynamic> cfg) {
    _attendees = {for (final a in (cfg['att'] as List<dynamic>? ?? const [])) '$a'};
    _treatAll = cfg['treatAll'] == true;
    final saved = cfg['lines'] as List<dynamic>? ?? const [];
    if (saved.isEmpty) return;
    _lines.clear();
    for (final raw in saved) {
      final m = raw as Map<String, dynamic>;
      final qty = (m['q'] as int).clamp(1, 999);
      final l = _Line(_uuid.v4(), m['n'] as String, qty, m['u'] as int, 0);
      final people = (m['p'] as List<dynamic>? ?? const []).map((s) => {for (final x in (s as List<dynamic>)) '$x'}).toList();
      final treat = (m['t'] as List<dynamic>? ?? const []).map((x) => x == true).toList();
      for (var i = 0; i < qty; i++) {
        if (i < people.length) l.people[i] = people[i];
        if (i < treat.length) l.treat[i] = treat[i];
      }
      _lines.add(l);
    }
  }

  void _setAttendees(Set<String> ids) {
    setState(() {
      _attendees = ids;
      for (final l in _lines) {
        l.stripFriends(ids);
      }
    });
  }

  /// What each friend owes, with what they had written out for the reminder message.
  List<Debt> _debts(String? txnId, String shop) {
    final split = _split;
    final out = <Debt>[];
    for (final fid in _attendees) {
      final owed = split[fid] ?? 0;
      if (owed <= 0) continue;
      final counts = <String, int>{};
      for (final l in _lines) {
        for (var i = 0; i < l.qty; i++) {
          if (l.people[i].contains(fid) && !l.treat[i]) {
            final label = l.people[i].length > 1 ? '${l.name} (shared)' : l.name;
            counts[label] = (counts[label] ?? 0) + 1;
          }
        }
      }
      out.add(Debt(
        id: _uuid.v4(),
        friendId: fid,
        date: _date,
        title: shop,
        cents: owed,
        items: _lines.isEmpty ? const ['even split'] : [for (final e in counts.entries) e.value > 1 ? '${e.key} x${e.value}' : e.key],
        txnId: txnId,
      ));
    }
    return out;
  }

  int get _itemsSum => _lines.fold<int>(0, (s, l) => s + l.total);

  void _resetTotal() => _total = _itemsSum + _service + _sst;

  Future<int?> _askMoney(String title, int current) {
    final c = TextEditingController(text: current == 0 ? '' : (current / 100).toStringAsFixed(2));
    return showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(controller: c, autofocus: true, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: const InputDecoration(prefixText: 'RM ')),
        actions: [
          TextButton(onPressed: () => ctx.pop(), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final neg = c.text.trim().startsWith('-');
              final v = parseCents(c.text);
              ctx.pop(v == null ? null : (neg ? -v : v));
            },
            child: const Text('OK', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Future<void> _editLine(_Line? line) async {
    final name = TextEditingController(text: line?.name ?? '');
    final qtyC = TextEditingController(text: '${line?.qty ?? 1}');
    final price = TextEditingController(text: line == null ? '' : (line.unit / 100).toStringAsFixed(2));
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(line == null ? 'Add item' : 'Edit item'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, autofocus: true, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Item')),
          const SizedBox(height: 12),
          Row(children: [
            SizedBox(width: 90, child: TextField(controller: qtyC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Qty'))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: price, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: const InputDecoration(labelText: 'Price each', prefixText: 'RM '))),
          ]),
        ]),
        actions: [
          if (line != null) TextButton(onPressed: () => ctx.pop('remove'), child: const Text('Remove', style: TextStyle(color: Brand.danger))),
          TextButton(onPressed: () => ctx.pop(), child: const Text('Cancel')),
          TextButton(onPressed: () => ctx.pop('ok'), child: const Text('OK', style: TextStyle(fontWeight: FontWeight.w800))),
        ],
      ),
    );
    if (result == null) return;
    setState(() {
      if (result == 'remove') {
        _lines.remove(line);
        return;
      }
      final neg = price.text.trim().startsWith('-');
      final v = parseCents(price.text);
      final n = name.text.trim();
      if (v == null || n.isEmpty) return;
      final cents = neg ? -v : v;
      final qty = (int.tryParse(qtyC.text.trim()) ?? 1).clamp(1, 999);
      if (line == null) {
        _lines.add(_Line(_uuid.v4(), n, qty, cents, qty));
      } else {
        final wasNone = line.mine <= 0;
        line
          ..name = n
          ..unit = cents;
        line.resize(qty, fillMine: !wasNone);
      }
    });
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
    final merchant = _merchant.text.trim();
    final catId = _categoryId ?? cats.where((c) => c.kind == 'spend').firstOrNull?.id;
    final share = _share;
    String? err;
    if (merchant.isEmpty) {
      err = 'Where was this? Add the shop name.';
    } else if (share <= 0 && !(widget.editId == null && _attendees.any((f) => (_split[f] ?? 0) > 0))) {
      // (a saved receipt always needs some share of yours; a brand new bill your friends fully cover is saved as debts only)
      err = _lines.isEmpty ? 'Set the total above zero.' : 'Tick at least one item that is yours.';
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

    if (share <= 0) {
      // Your friends cover the whole bill: nothing of yours to log, only what they owe you.
      await ref.read(ledgerProvider.notifier).addDebts(_debts(null, merchant));
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      context.go('/');
      messenger
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('Saved for your friends. Nothing added to your spending.')));
      return;
    }
    if (widget.editId == null && !await confirmNotDuplicate(context, ref, merchant: merchant, amountCents: share, date: _date, reference: _reference)) {
      if (mounted) setState(() => _saving = false);
      return;
    }
    final now = nowIso();
    final id = _existing?.id ?? _uuid.v4();
    await ref.read(dbProvider).saveTxn(
          TxnsCompanion.insert(
            id: id,
            spentAt: _date,
            merchant: merchant,
            amountCents: share,
            categoryId: catId!,
            paymentType: _payment,
            createdAt: _existing?.createdAt ?? now,
            updatedAt: now,
            receiptTotalCents: Value(_lines.isEmpty && _attendees.isEmpty ? null : _total),
            taxCents: Value(_tax),
            direction: const Value('spend'),
            countsTowardCap: Value(_payment != 'spaylater'),
            note: Value(_existing?.note),
            source: Value(_existing?.source ?? (_isImport ? 'import' : 'scan')),
            reference: Value(_existing?.reference ?? _reference),
            confidence: Value(_confidence),
          ),
          [for (final r in _rows) TxnItemsCompanion.insert(id: r.id, txnId: id, name: r.name, priceCents: r.price, included: Value(r.included))],
        );
    await ref.read(dbProvider).learnRule(merchant, catId);
    await ref.read(ledgerProvider.notifier).saveSplit(id, _splitConfig(), _debts(id, merchant)); // new or edited: friends' shares follow the receipt
    ref.read(syncProvider.notifier).run();
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (widget.editId != null) {
      context.pop();
    } else {
      context.go('/');
    }
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text('Saved ${rm(share)}')));
  }

  @override
  Widget build(BuildContext context) {
    final cats = ref.watch(categoriesProvider).asData?.value ?? const <Cat>[];
    final spendCats = {for (final c in cats.where((c) => c.kind == 'spend')) c.id: c.name};
    final selectedCat = _categoryId ?? spendCats.keys.firstOrNull;
    final share = _share;
    final itemsSum = _itemsSum;
    final partial = _attendees.isNotEmpty || (_lines.isNotEmpty && _lines.any((l) => l.mine < l.qty));
    final ledger = ref.watch(ledgerProvider);
    final split = _split;
    const canSplit = true; // friends can be added to a saved receipt too; what they owe is redone when you save
    final gap = itemsSum + _tax - _total; // how far the items and charges are from the receipt total
    final mismatch = _lines.isNotEmpty && gap.abs() > 10;

    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator(color: Brand.forest)));
    if (widget.editId != null && _existing == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('This entry is gone.')));

    final notes = <String>[..._hints, if (_via == 'offline') 'Read on your phone without the server. Double-check the numbers.'];

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close), tooltip: 'Close', onPressed: () => context.pop()),
        title: Text(widget.editId != null ? 'Edit receipt' : 'Check and save', style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          children: [
            if (notes.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Brand.amber.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(14)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final n in notes) Text(n, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))]),
              ),
            TextField(controller: _merchant, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Where')),
            const SizedBox(height: 12),
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(14),
              child: InputDecorator(decoration: const InputDecoration(labelText: 'Date', suffixIcon: Icon(Icons.calendar_today_outlined, size: 20)), child: Text(_date == todayKL() ? 'Today · ${shortDate(_date)}' : shortDate(_date), style: const TextStyle(fontSize: 16))),
            ),
            if (canSplit) ...[
              const SizedBox(height: 20),
              Row(children: [
                const Expanded(child: FieldLabel('Split with friends')),
                if (_isImport) TextButton(onPressed: _creditFriend, child: const Text('A friend paid me', style: TextStyle(color: Brand.forest, fontWeight: FontWeight.w600))),
              ]),
              FriendChips(selected: _attendees, onChanged: _setAttendees),
              if (_attendees.isNotEmpty && _lines.isEmpty)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('I am treating them'),
                  subtitle: const Text('Counts as your spending, they owe nothing', style: TextStyle(fontSize: 12, color: Brand.muted)),
                  value: _treatAll,
                  activeThumbColor: Brand.paper,
                  activeTrackColor: Brand.forest,
                  onChanged: (v) => setState(() => _treatAll = v),
                ),
            ],
            const SizedBox(height: 22),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Items', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              TextButton.icon(onPressed: () => _editLine(null), icon: const Icon(Icons.add, size: 18), label: const Text('Add item'), style: TextButton.styleFrom(foregroundColor: Brand.forest)),
            ]),
            if (_lines.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(_attendees.isEmpty ? 'Untick anything that is not yours, like a friend\'s order.' : 'Tap who had each item. Tap two people to share it. Turn on Treat if you are paying for them.', style: const TextStyle(fontSize: 13, color: Brand.muted)),
              ),
            if (_lines.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Text('No items read. You can add them, or just set the total below.', style: TextStyle(color: Brand.muted))),
            for (final l in _lines)
              if (_attendees.isNotEmpty)
                _friendLine(l)
              else
              Container(
                decoration: const BoxDecoration(border: Border(top: BorderSide(color: Brand.line))),
                child: Row(children: [
                  Checkbox(
                    value: l.mine >= l.qty ? true : (l.mine <= 0 ? false : null),
                    tristate: true,
                    activeColor: Brand.forest,
                    onChanged: (_) => setState(() => l.setMine(l.mine >= l.qty ? 0 : l.qty)),
                  ),
                  Expanded(
                    child: InkWell(
                      onTap: () => _editLine(l),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(l.name, style: TextStyle(fontSize: 15, color: l.mine > 0 ? Brand.ink : Brand.muted, decoration: l.mine > 0 ? null : TextDecoration.lineThrough)),
                              if (l.qty > 1) Text('${l.qty} × ${rm(l.unit)}', style: const TextStyle(fontSize: 12, color: Brand.muted)),
                            ]),
                          ),
                          if (l.qty > 1)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                IconButton(visualDensity: VisualDensity.compact, tooltip: 'Fewer are mine', icon: const Icon(Icons.remove_circle_outline, size: 20), onPressed: l.mine > 0 ? () => setState(() => l.setMine(l.mine - 1)) : null),
                                Text('${l.mine}/${l.qty}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                                IconButton(visualDensity: VisualDensity.compact, tooltip: 'More are mine', icon: const Icon(Icons.add_circle_outline, size: 20), onPressed: l.mine < l.qty ? () => setState(() => l.setMine(l.mine + 1)) : null),
                              ]),
                            ),
                          Text(rm(l.total), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: l.mine > 0 ? Brand.ink : Brand.muted)),
                        ]),
                      ),
                    ),
                  ),
                ]),
              ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: Brand.card, borderRadius: BorderRadius.circular(20), border: Border.all(color: Brand.line)),
              child: Column(children: [
                if (_lines.isNotEmpty) _sumRow('Items', rm(itemsSum)),
                if (_service != 0) _chargeRow('Service charge', _service, (v) => _service = v),
                if (_sst != 0) _chargeRow(_sstLabel, _sst, (v) => _sst = v),
                if (mismatch)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text('Items${_tax != 0 ? ' and charges' : ''} come to ${rm(itemsSum + _tax)}, but the receipt total is ${rm(_total)}. Check the quantities, prices and tax.', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Brand.danger)),
                  ),
                InkWell(
                  onTap: () async {
                    final v = await _askMoney('Receipt total', _total);
                    if (v != null && v >= 0) setState(() => _total = v);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Text('Receipt total', style: TextStyle(fontSize: 14, color: Brand.muted)),
                      Row(children: [Text(rm(_total), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)), const SizedBox(width: 6), const Icon(Icons.edit_outlined, size: 16, color: Brand.muted)]),
                    ]),
                  ),
                ),
                const Divider(color: Brand.line, height: 22),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(partial ? 'Your share' : 'You pay', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  Text(rm(share), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -1, color: Brand.forest)),
                ]),
                if (partial) const Padding(padding: EdgeInsets.only(top: 6), child: Align(alignment: Alignment.centerRight, child: Text('Tax is split in proportion to what each person had.', style: TextStyle(fontSize: 12, color: Brand.muted)))),
                if (canSplit)
                  for (final fid in _attendees)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Text('${ledger.friend(fid)?.name ?? 'Friend'} owes you', style: const TextStyle(fontSize: 14, color: Brand.muted)),
                        Text(rm(split[fid] ?? 0), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      ]),
                    ),
              ]),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(onPressed: _addCharge, icon: const Icon(Icons.add, size: 18), label: const Text('Add tax or service charge'), style: TextButton.styleFrom(foregroundColor: Brand.forest)),
            ),
            const SizedBox(height: 14),
            const FieldLabel('Category'),
            PickChips<int>(options: spendCats, selected: selectedCat, onSelected: (id) => setState(() => _categoryId = id)),
            const SizedBox(height: 18),
            const FieldLabel('Paid with'),
            PickChips<String>(options: _payments, selected: _payment, onSelected: (p) => setState(() => _payment = p)),
            if (_payment == 'spaylater') const Padding(padding: EdgeInsets.only(top: 8), child: Text('Stays out of your weekly cap. You pay it back through the SPayLater schedule.', style: TextStyle(fontSize: 13, color: Brand.muted))),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 14), child: Text(_error!, style: const TextStyle(color: Brand.danger, fontWeight: FontWeight.w600))),
            const SizedBox(height: 22),
            FilledButton(onPressed: _saving ? null : () => _save(cats), child: Text('Save ${rm(share)}')),
          ],
        ),
      ),
    );
  }

  /// One receipt item when friends are at the table: who had it, per unit.
  Widget _friendLine(_Line l) {
    final friends = ref.watch(ledgerProvider).friends.where((f) => _attendees.contains(f.id)).toList();
    Widget chips(int i) {
      final people = l.people[i];
      final hasFriend = people.any((p) => p != me);
      Widget chip(String id, String label) => FilterChip(
            label: Text(label),
            selected: people.contains(id),
            visualDensity: VisualDensity.compact,
            onSelected: (on) => setState(() {
              final next = {...people};
              on ? next.add(id) : next.remove(id);
              l.people[i] = next;
              if (next.every((p) => p == me)) l.treat[i] = false;
            }),
            selectedColor: Brand.forest,
            labelStyle: TextStyle(color: people.contains(id) ? Brand.paper : Brand.ink, fontWeight: FontWeight.w600, fontSize: 13),
            checkmarkColor: Brand.paper,
            backgroundColor: Brand.card,
            side: const BorderSide(color: Brand.line),
          );
      return Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        chip(me, 'Me'),
        for (final f in friends) chip(f.id, f.name),
        if (hasFriend)
          FilterChip(
            label: const Text('Treat'),
            selected: l.treat[i],
            visualDensity: VisualDensity.compact,
            onSelected: (on) => setState(() => l.treat[i] = on),
            selectedColor: Brand.amber,
            labelStyle: const TextStyle(color: Brand.ink, fontWeight: FontWeight.w700, fontSize: 13),
            showCheckmark: false,
            backgroundColor: Brand.card,
            side: const BorderSide(color: Brand.line),
          ),
      ]);
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: Brand.line))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          onTap: () => _editLine(l),
          child: Row(children: [
            Expanded(child: Text(l.qty > 1 ? '${l.name}  ${l.qty} × ${rm(l.unit)}' : l.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
            Text(rm(l.total), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ]),
        ),
        const SizedBox(height: 6),
        if (l.qty == 1)
          chips(0)
        else
          for (var i = 0; i < l.qty; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                SizedBox(width: 26, child: Text('#${i + 1}', style: const TextStyle(fontSize: 12, color: Brand.muted))),
                Expanded(child: chips(i)),
              ]),
            ),
      ]),
    );
  }

  /// A payment screenshot that is a friend paying you back: record it against their balance instead of as spending.
  Future<void> _creditFriend() async {
    final ledger = ref.read(ledgerProvider);
    if (ledger.friends.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add a friend first with the + Friend chip.')));
      return;
    }
    final guess = _merchant.text.trim().toLowerCase();
    final friends = [...ledger.friends]..sort((a, b) {
        final am = guess.isNotEmpty && (guess.contains(a.name.toLowerCase()) || a.name.toLowerCase().contains(guess));
        final bm = guess.isNotEmpty && (guess.contains(b.name.toLowerCase()) || b.name.toLowerCase().contains(guess));
        return am == bm ? 0 : (am ? -1 : 1);
      });
    final pick = await showModalBottomSheet<Friend>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(padding: EdgeInsets.fromLTRB(20, 16, 20, 8), child: Align(alignment: Alignment.centerLeft, child: Text('Who paid you?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)))),
          for (final f in friends)
            ListTile(title: Text(f.name), trailing: Text(ledger.balanceOf(f.id) > 0 ? 'owes ${rm(ledger.balanceOf(f.id))}' : '', style: const TextStyle(color: Brand.muted)), onTap: () => ctx.pop(f)),
        ]),
      ),
    );
    if (pick == null || !mounted) return;
    final cents = await _askMoney('${pick.name} paid you', _total);
    if (cents == null || cents <= 0 || !mounted) return;
    await ref.read(ledgerProvider.notifier).addPayment(pick.id, cents, date: _date);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    context.go('/');
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text('${pick.name} paid you ${rm(cents)}')));
  }

  /// A tax or charge line read from the receipt. Tap to change the amount; set it to 0 to remove it.
  Widget _chargeRow(String label, int cents, void Function(int) set) => InkWell(
        onTap: () async {
          final v = await _askMoney(label, cents);
          if (v == null || v < 0) return;
          setState(() {
            set(v);
            _resetTotal();
          });
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(label, style: const TextStyle(fontSize: 14, color: Brand.muted)),
            Row(children: [Text(rm(cents), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)), const SizedBox(width: 6), const Icon(Icons.edit_outlined, size: 16, color: Brand.muted)]),
          ]),
        ),
      );

  /// For shops whose receipt does not show a tax the app should add: pick service charge (10%) or SST (6%).
  /// The amount is worked out as a starting point and can be edited before it is added.
  Future<void> _addCharge() async {
    final pick = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: const Text('Service charge (10%)'), subtitle: const Text('Worked out on the items'), onTap: () => ctx.pop('service')),
          ListTile(title: const Text('SST / service tax (6%)'), subtitle: const Text('Worked out on the items plus any service charge'), onTap: () => ctx.pop('sst')),
        ]),
      ),
    );
    if (pick == null) return;
    final base = _itemsSum;
    final guess = pick == 'service' ? (base * 0.10).round() : ((base + _service) * 0.06).round();
    final v = await _askMoney(pick == 'service' ? 'Service charge' : 'SST / service tax', guess);
    if (v == null || v <= 0) return;
    setState(() {
      if (pick == 'service') {
        _service = v;
      } else {
        _sst = v;
        _sstLabel = 'SST / service tax';
      }
      _resetTotal();
    });
  }

  Widget _sumRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: const TextStyle(fontSize: 14, color: Brand.muted)), Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))]),
      );
}

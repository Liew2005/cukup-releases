import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/format.dart';
import '../core/pay_notif.dart';
import '../data/db.dart';
import '../data/detected.dart';
import '../data/providers.dart';
import '../theme/theme.dart';
import 'cap_switch.dart';
import 'chips.dart';
import 'dup_dialog.dart';

const _payments = {'ewallet': 'E-wallet', 'debit': 'Debit', 'credit_card': 'Credit card', 'cash': 'Cash'};

String shortWhen(Detected d) => '${d.date.substring(8, 10)}/${d.date.substring(5, 7)} ${d.time}';

/// Home: payments Cukup noticed, waiting for a yes or no. Shows nothing when there are none.
/// Tap a row to check the details first; Save keeps the guess shown under it.
class DetectedCard extends ConsumerWidget {
  const DetectedCard({super.key});

  Future<void> _save(BuildContext context, WidgetRef ref, Detected d) async {
    final c = ref.read(detectedProvider.notifier);
    if (c.payFor(d) == null) {
      context.push('/confirm/${d.id}'); // a card Cukup has not been told about: ask
      return;
    }
    if (!await confirmNotDuplicate(context, ref, merchant: d.merchant, amountCents: d.cents, date: d.date)) return;
    await c.save(d);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(detectedProvider);
    if (pending.isEmpty) return const SizedBox.shrink();
    final c = ref.read(detectedProvider.notifier);
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
        decoration: BoxDecoration(color: Brand.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: Brand.amber, width: 1.5)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(pending.length == 1 ? 'Did you pay this?' : 'Did you pay these?', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          const Text('Not saved yet. Nothing is recorded until you tap Save.', style: TextStyle(fontSize: 12, color: Brand.muted)),
          for (final d in pending.take(5))
            InkWell(
              onTap: () => context.push('/confirm/${d.id}'),
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${rm(d.cents)} · ${d.merchant}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      Text([c.guessFor(d)?.name, _payments[c.payFor(d)] ?? d.card, d.app, shortWhen(d)].whereType<String>().join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Brand.muted)),
                    ]),
                  ),
                  TextButton(onPressed: () => _save(context, ref, d), style: TextButton.styleFrom(foregroundColor: Brand.forest), child: const Text('Save', style: TextStyle(fontWeight: FontWeight.w800))),
                  IconButton(icon: const Icon(Icons.delete_outline, size: 20), tooltip: 'Delete, do not log it', color: Brand.muted, onPressed: () => c.dismiss(d)),
                ]),
              ),
            ),
          if (pending.length > 5) Padding(padding: const EdgeInsets.only(top: 6, bottom: 6), child: Text('and ${pending.length - 5} more', style: const TextStyle(fontSize: 12, color: Brand.muted))),
        ]),
      ),
    );
  }
}

/// The sheet that opens when you tap a detected payment (on the banner or the Home card):
/// amount, shop, category, how it was paid and whether it counts toward the week. Save or Delete.
class ConfirmPage extends ConsumerStatefulWidget {
  const ConfirmPage({super.key, required this.id});
  final String id;
  @override
  ConsumerState<ConfirmPage> createState() => _ConfirmPageState();
}

class _ConfirmPageState extends ConsumerState<ConfirmPage> {
  final _amount = TextEditingController();
  final _shop = TextEditingController();
  Detected? _d;
  bool _loading = true;
  bool _saving = false;
  int? _catId;
  bool _catTouched = false;
  String? _pay;
  bool? _capOverride;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _amount.dispose();
    _shop.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final c = ref.read(detectedProvider.notifier);
    await c.refresh(); // the banner may have been tapped while the app was closed
    final d = ref.read(detectedProvider).where((x) => x.id == widget.id).firstOrNull;
    if (!mounted) return;
    setState(() {
      _d = d;
      _loading = false;
      if (d != null) {
        _amount.text = (d.cents / 100).toStringAsFixed(2);
        _shop.text = d.merchant;
        _catId = c.guessFor(d)?.id;
        _pay = c.payFor(d);
      }
    });
  }

  Future<void> _save(List<Cat> cats) async {
    final d = _d!;
    final cents = parseCents(_amount.text);
    final shop = _shop.text.trim();
    final catId = _catId ?? cats.firstOrNull?.id;
    String? err;
    if (cents == null || cents <= 0 || cents > 100000000) {
      err = 'Enter an amount above zero, like 12.50.';
    } else if (shop.isEmpty) {
      err = 'Where did you spend it?';
    } else if (_pay == null) {
      err = 'Is this card credit or debit? Pick one under Paid with.';
    } else if (catId == null) {
      err = 'Categories have not loaded yet. Open Home once while online.';
    }
    if (err != null) return setState(() => _error = err);
    setState(() {
      _saving = true;
      _error = null;
    });
    if (!await confirmNotDuplicate(context, ref, merchant: shop, amountCents: cents!, date: d.date)) {
      if (mounted) setState(() => _saving = false);
      return;
    }
    final catName = cats.where((c) => c.id == catId).firstOrNull?.name;
    await ref.read(detectedProvider.notifier).save(
          d,
          ConfirmChoice(merchant: shop, cents: cents, categoryId: _catTouched || shop != d.merchant ? catId : null, paymentType: _pay, countsTowardCap: _capOverride ?? capDefault(catName)),
        );
    if (mounted) context.pop();
  }

  Future<void> _delete() async {
    await ref.read(detectedProvider.notifier).dismiss(_d!);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final cats = (ref.watch(categoriesProvider).asData?.value ?? const <Cat>[]).where((c) => c.kind == 'spend').toList();
    final options = {for (final c in cats) c.id: c.name};
    final selected = _catId != null && options.containsKey(_catId) ? _catId : options.keys.firstOrNull;
    final d = _d;

    final Widget body;
    if (_loading) {
      body = const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator(color: Brand.forest)));
    } else if (d == null) {
      body = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Already dealt with', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text('This payment was saved or deleted earlier.', style: TextStyle(color: Brand.muted)),
        const SizedBox(height: 16),
        FilledButton(onPressed: () => context.pop(), child: const Text('Close')),
      ]);
    } else {
      body = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Text('Save this payment?', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
          IconButton(icon: const Icon(Icons.close), tooltip: 'Decide later', onPressed: () => context.pop()),
        ]),
        Text(['Seen in ${d.app}', ...d.alsoSeenBy.map((a) => 'and $a'), shortWhen(d)].join(' · '), style: const TextStyle(fontSize: 12, color: Brand.muted)),
        const SizedBox(height: 14),
        TextField(controller: _amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800), decoration: const InputDecoration(labelText: 'Amount', prefixText: 'RM ')),
        const SizedBox(height: 12),
        TextField(controller: _shop, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Where')),
        const SizedBox(height: 16),
        const FieldLabel('Category'),
        PickChips<int>(options: options, selected: selected, onSelected: (id) => setState(() {
          _catId = id;
          _catTouched = true;
        })),
        const SizedBox(height: 16),
        FieldLabel(d.card == null ? 'Paid with' : 'Paid with · ${d.card}'),
        PickChips<String>(options: _payments, selected: _pay, onSelected: (p) => setState(() => _pay = p)),
        if (d.card != null && ref.read(detectedProvider.notifier).payFor(d) == null)
          const Padding(padding: EdgeInsets.only(top: 6), child: Text('First time Cukup has seen this card. Pick credit or debit and it will remember.', style: TextStyle(fontSize: 12, color: Brand.muted))),
        CapSwitch(value: _capOverride ?? capDefault(options[selected]), onChanged: (v) => setState(() => _capOverride = v)),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 6, bottom: 6), child: Text(_error!, style: const TextStyle(color: Brand.danger, fontWeight: FontWeight.w600))),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: _saving ? null : _delete, style: OutlinedButton.styleFrom(foregroundColor: Brand.danger, side: const BorderSide(color: Brand.line), minimumSize: const Size.fromHeight(52)), child: const Text('Delete'))),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: FilledButton(onPressed: _saving ? null : () => _save(cats), child: Text(_saving ? 'Saving...' : 'Save'))),
        ]),
      ]);
    }

    // A card that rises from the bottom over whatever screen was open.
    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: false, // the sheet pads itself above the keyboard
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => context.pop(),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            onTap: () {}, // taps inside the sheet do not close it
            child: Material(
              color: Brand.paper,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(padding: EdgeInsets.fromLTRB(20, 18, 20, 16 + MediaQuery.of(context).viewInsets.bottom), child: body),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../core/format.dart';
import '../core/time.dart';
import '../data/db.dart';
import '../data/ledger.dart';
import '../data/providers.dart';
import '../theme/theme.dart';

const _paymentLabels = {'cash': 'Cash', 'debit': 'Debit', 'ewallet': 'E-wallet', 'credit_card': 'Credit card', 'spaylater': 'SPayLater'};
const _sourceLabels = {'scan': 'Scanned receipt', 'manual': 'Added by hand', 'quick': 'Quick add', 'import': 'Shared screenshot', 'recurring': 'Recurring entry'};

String _when(String iso) {
  final d = DateTime.tryParse(iso);
  return d == null ? iso : DateFormat('d MMM y, HH:mm').format(d.toLocal());
}

class TxnDetailPage extends ConsumerWidget {
  const TxnDetailPage({super.key, required this.id});
  final String id;

  Future<void> _delete(BuildContext context, WidgetRef ref, Txn t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete this entry?'),
        content: Text('${t.merchant} · ${rm(t.amountCents)}'),
        actions: [
          TextButton(onPressed: () => c.pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => c.pop(true), child: const Text('Delete', style: TextStyle(color: Brand.danger, fontWeight: FontWeight.w800))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final db = ref.read(dbProvider);
    final messenger = ScaffoldMessenger.of(context);
    final ledger = ref.read(ledgerProvider.notifier);
    final snap = await ledger.removeForTxn(t.id); // what friends owe for this receipt goes with it
    await db.softDelete(t.id);
    ref.read(syncProvider.notifier).run();
    if (context.mounted) context.pop();
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text('Deleted ${t.merchant}'),
        action: SnackBarAction(
            label: 'Undo',
            textColor: Brand.amber,
            onPressed: () async {
              if (snap != null) await ledger.restoreSnapshot(snap);
              await db.restore(t.id);
              ref.read(syncProvider.notifier).run();
            }),
      ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(txnProvider(id)).asData?.value;
    final items = ref.watch(itemsProvider(id)).asData?.value ?? const <TxnItem>[];
    final cats = ref.watch(categoriesProvider).asData?.value ?? const <Cat>[];

    if (t == null || t.deletedAt != null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('This entry is gone.', style: TextStyle(color: Brand.muted))));
    }

    final income = t.direction == 'income';
    final later = t.paymentType == 'spaylater';
    final catName = cats.where((c) => c.id == t.categoryId).map((c) => c.name).firstOrNull ?? '—';
    final split = t.receiptTotalCents != null && t.receiptTotalCents != t.amountCents;
    final capNote = income ? 'No, income never counts' : later ? 'No, SPayLater is paid back through bills' : t.countsTowardCap ? 'Yes' : 'No';

    Widget row(String label, String value) => Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: Brand.line))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 118, child: Text(label, style: const TextStyle(fontSize: 14, color: Brand.muted))),
            Expanded(child: Text(value, textAlign: TextAlign.right, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
          ]),
        );

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), tooltip: 'Back', onPressed: () => context.pop()),
        actions: [
          IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'Edit', onPressed: () => context.push(items.isNotEmpty ? '/review/$id' : '/edit/$id')),
          IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Delete', onPressed: () => _delete(context, ref, t)),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          children: [
            Text(t.merchant, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
            const SizedBox(height: 6),
            Text(rm(t.amountCents, plus: income), style: TextStyle(fontSize: 44, fontWeight: FontWeight.w800, letterSpacing: -1.8, height: 1.05, color: income ? Brand.forest : Brand.ink)),
            if (split) Padding(padding: const EdgeInsets.only(top: 4), child: Text('Your share of a ${rm(t.receiptTotalCents!)} receipt', style: const TextStyle(fontSize: 14, color: Brand.muted))),
            const SizedBox(height: 20),
            row('Date', shortDate(t.spentAt)),
            row(income ? 'Type' : 'Category', income ? 'Income · $catName' : catName),
            if (!income) row('Paid with', _paymentLabels[t.paymentType] ?? t.paymentType),
            row('Counts toward cap', capNote),
            row('Added', _sourceLabels[t.source] ?? t.source),
            if (t.note != null) row('Note', t.note!),
            if (t.reference != null) row('Reference', t.reference!),
            if (items.isNotEmpty) ...[
              const SizedBox(height: 26),
              const Text('Items on the receipt', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              for (final i in items)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: const BoxDecoration(border: Border(top: BorderSide(color: Brand.line))),
                  child: Row(children: [
                    Icon(i.included ? Icons.check_circle : Icons.circle_outlined, size: 20, color: i.included ? Brand.forest : Brand.muted),
                    const SizedBox(width: 10),
                    Expanded(child: Text(i.name, style: TextStyle(fontSize: 15, color: i.included ? Brand.ink : Brand.muted, decoration: i.included ? null : TextDecoration.lineThrough))),
                    Text(rm(i.priceCents), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: i.included ? Brand.ink : Brand.muted)),
                  ]),
                ),
              if (t.taxCents > 0) row('Tax', rm(t.taxCents)),
              if (t.receiptTotalCents != null) row('Receipt total', rm(t.receiptTotalCents!)),
            ],
            const SizedBox(height: 22),
            Text('Created ${_when(t.createdAt)}${t.updatedAt != t.createdAt ? ' · Edited ${_when(t.updatedAt)}' : ''}', style: const TextStyle(fontSize: 12, color: Brand.muted)),
          ],
        ),
      ),
    );
  }
}


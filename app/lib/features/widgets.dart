import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/format.dart';
import '../core/time.dart';
import '../data/db.dart';
import '../data/providers.dart';
import '../theme/theme.dart';

class TxnTile extends ConsumerWidget {
  const TxnTile({super.key, required this.txn});
  final Txn txn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cats = ref.watch(categoriesProvider).asData?.value ?? const <Cat>[];
    final catName = cats.where((c) => c.id == txn.categoryId).map((c) => c.name).firstOrNull ?? '';
    final income = txn.direction == 'income';
    final later = txn.paymentType == 'spaylater';
    return InkWell(
      onTap: () => context.push('/txn/${txn.id}'),
      child: Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: Brand.line))),
      child: Row(children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: income ? Brand.amber.withValues(alpha: 0.35) : Brand.mint, shape: BoxShape.circle),
          child: Icon(income ? Icons.south_west_rounded : Icons.north_east_rounded, size: 18, color: Brand.forest),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(txn.merchant, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            Text([catName, shortDate(txn.spentAt), if (later) 'SPayLater'].where((s) => s.isNotEmpty).join(' · '), style: const TextStyle(fontSize: 13, color: Brand.muted)),
          ]),
        ),
        Text(rm(txn.amountCents, plus: income), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: income ? Brand.forest : Brand.ink, fontFeatures: const [FontFeature.tabularFigures()])),
      ]),
    ));
  }
}


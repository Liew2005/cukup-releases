import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import '../core/guards.dart';
import '../core/time.dart';
import '../data/db.dart';
import '../data/providers.dart';
import '../theme/theme.dart';

/// Asks before saving something that looks like an entry you already have.
/// Returns true when there is no match, or when the user taps "Save anyway".
Future<bool> confirmNotDuplicate(BuildContext context, WidgetRef ref, {required String merchant, required int amountCents, required String date, String? reference, String? ignoreId, String direction = 'spend'}) async {
  final recent = await ref.read(dbProvider).watchTxns(limit: 300).first;
  final Txn? dup = findDuplicate(recent, merchant: merchant, amountCents: amountCents, date: date, reference: reference, ignoreId: ignoreId, direction: direction);
  if (dup == null || !context.mounted) return true;
  final save = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Already logged?'),
      content: Text('You have ${rm(dup.amountCents)} at ${dup.merchant} on ${shortDate(dup.spentAt)}. This looks like the same one.'),
      actions: [
        TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('Save anyway', style: TextStyle(color: Brand.forest, fontWeight: FontWeight.w800))),
      ],
    ),
  );
  return save == true;
}

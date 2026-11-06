import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/csv.dart';
import '../core/time.dart';
import '../data/db.dart';

/// Builds a CSV from [txns] on the phone and opens the share sheet (save to Drive, email, etc.).
Future<void> exportCsv(BuildContext context, List<Txn> txns, Map<int, String> categoryNames, {String label = 'all'}) async {
  final messenger = ScaffoldMessenger.of(context);
  if (txns.isEmpty) {
    messenger.showSnackBar(const SnackBar(content: Text('Nothing to export yet.')));
    return;
  }
  try {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/cukup-$label-${todayKL()}.csv');
    await file.writeAsString('﻿${buildCsv(txns, categoryNames)}'); // BOM so Excel reads accents and Chinese correctly
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'text/csv')], subject: 'Cukup export'));
  } catch (_) {
    messenger.showSnackBar(const SnackBar(content: Text('Could not create the export. Try again.')));
  }
}

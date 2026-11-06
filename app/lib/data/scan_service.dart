import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../core/import_parser.dart';
import '../core/time.dart';
import 'api.dart';
import 'local_parser.dart';
import 'receipt_models.dart';

class ScanFailure implements Exception {
  ScanFailure(this.message);
  final String message;
}

/// Photo -> text on the phone (ML Kit) -> structured receipt (server if reachable, otherwise offline rules).
class ScanService {
  ScanService(this._api);
  final ApiClient _api;

  Future<ParsedReceipt> scan(String imagePath, {bool payment = false}) async {
    final String text;
    try {
      text = await _readText(imagePath);
    } catch (_) {
      throw ScanFailure('Could not read that photo.');
    } finally {
      try {
        await File(imagePath).delete(); // the photo is not kept
      } catch (_) {}
    }
    if (text.trim().length < 10) throw ScanFailure('No text found. Try again with the whole receipt in frame and good light.');

    if (payment) {
      // A Touch 'n Go or bank screenshot: pull out amount, payee, reference and date. No server needed.
      final p = parseImport(text, today: todayKL());
      if (p != null) {
        return ParsedReceipt(
          merchant: p.payee,
          date: p.date,
          items: [],
          totalCents: p.amountCents,
          confidence: p.payee != null ? 0.85 : 0.6,
          warnings: p.payee == null ? ['no_merchant'] : const [],
          via: 'offline',
        )
          ..reference = p.reference
          ..isImport = true;
      }
    }

    final online = (await Connectivity().checkConnectivity()).any((r) => r != ConnectivityResult.none);
    if (online) {
      try {
        final json = await _api.parseReceipt(text.length > 7900 ? text.substring(0, 7900) : text).timeout(const Duration(seconds: 14));
        return ParsedReceipt.fromServer(json);
      } catch (_) {
        // Server slow, down, or rate limited: fall through to the offline parser.
      }
    }
    return LocalReceiptParser.parse(text, today: todayKL());
  }

  /// Receipts print the name on the left and the price on the right, and ML Kit often returns them as
  /// separate lines. Rejoin lines that sit on the same row so "Nasi lemak" and "9.80" stay together.
  Future<String> _readText(String path) async {
    try {
      return await _readWith(TextRecognitionScript.chinese, path); // reads Chinese and Latin together
    } catch (_) {
      return _readWith(TextRecognitionScript.latin, path);
    }
  }

  Future<String> _readWith(TextRecognitionScript script, String path) async {
    final recognizer = TextRecognizer(script: script);
    try {
      final result = await recognizer.processImage(InputImage.fromFilePath(path));
      final lines = <TextLine>[for (final b in result.blocks) ...b.lines];
      if (lines.isEmpty) return '';
      lines.sort((a, b) => a.boundingBox.center.dy.compareTo(b.boundingBox.center.dy));
      final rows = <List<TextLine>>[];
      for (final l in lines) {
        if (rows.isNotEmpty) {
          final row = rows.last;
          final cy = row.map((e) => e.boundingBox.center.dy).reduce((a, b) => a + b) / row.length;
          final h = row.map((e) => e.boundingBox.height).reduce((a, b) => a + b) / row.length;
          if ((l.boundingBox.center.dy - cy).abs() < h * 0.6) {
            row.add(l);
            continue;
          }
        }
        rows.add([l]);
      }
      return rows.map((r) {
        r.sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left));
        return r.map((e) => e.text).join(' ');
      }).join('\n');
    } finally {
      await recognizer.close();
    }
  }
}

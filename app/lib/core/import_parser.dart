/// What could be read from a Touch 'n Go or bank payment screenshot.
class ImportedPayment {
  const ImportedPayment({required this.amountCents, this.payee, this.reference, this.date});
  final int amountCents;
  final String? payee;
  final String? reference;
  final String? date; // YYYY-MM-DD
}

const _months = {'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6, 'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12};

final _amountRe = RegExp(r'(?:RM|MYR)\s*-?\s*([0-9]{1,3}(?:,[0-9]{3})*(?:\.[0-9]{1,2})?|[0-9]+(?:\.[0-9]{1,2})?)', caseSensitive: false);
final _labelRe = RegExp(r'^(?:paid\s+to|pay\s+to|transfer(?:red)?\s+to|merchant(?:\s+name)?|payee|recipient(?:\s+name)?|beneficiary(?:\s+name)?|to)\s*[:\-]?\s*(.*)$', caseSensitive: false);
final _refRe = RegExp(r'(?:\bref(?:erence)?\b(?:\s*(?:no|number|id)\b)?|transaction\s*(?:no|number|id)|txn\s*(?:no|id)|trans\s*id)\.?\s*[:#]?\s*([A-Za-z0-9]{6,})', caseSensitive: false);
final _amountLabelRe = RegExp(r'amount|total|paid|payment|pay\b|debit', caseSensitive: false);

int? _cents(String s) {
  final v = double.tryParse(s.replaceAll(',', ''));
  return v == null ? null : (v * 100).round();
}

/// Reads amount, payee, reference and date from OCR text of a payment screenshot. Null when no amount is found.
/// [today] (YYYY-MM-DD) rejects dates in the future.
ImportedPayment? parseImport(String text, {required String today}) {
  final lines = [for (final l in text.split('\n')) l.trim()].where((l) => l.isNotEmpty).toList();
  if (lines.isEmpty) return null;

  // Amount: prefer a line labelled amount/total/paid, then the first RM figure.
  int? amount;
  for (final l in lines) {
    final m = _amountRe.firstMatch(l);
    if (m != null && _amountLabelRe.hasMatch(l)) {
      amount = _cents(m.group(1)!);
      if (amount != null && amount > 0) break;
    }
  }
  if (amount == null || amount <= 0) {
    for (final l in lines) {
      final m = _amountRe.firstMatch(l);
      final c = m == null ? null : _cents(m.group(1)!);
      if (c != null && c > 0) {
        amount = c;
        break;
      }
    }
  }
  if (amount == null || amount <= 0) return null;

  // Payee: "Paid to X" / "To X" on one row, or the label alone with the name on the next row.
  String? payee;
  for (var i = 0; i < lines.length && payee == null; i++) {
    final m = _labelRe.firstMatch(lines[i]);
    if (m == null) continue;
    var v = m.group(1)!.trim();
    if (v.isEmpty && i + 1 < lines.length) v = lines[i + 1];
    if (v.isNotEmpty && !_amountRe.hasMatch(v) && v.length <= 60) payee = v;
  }

  String? reference;
  for (var i = 0; i < lines.length && reference == null; i++) {
    final m = _refRe.firstMatch(lines[i]);
    if (m != null) {
      reference = m.group(1);
    } else if (RegExp(r'^(?:ref(?:erence)?|transaction)\s*(?:no|number|id)?\.?\s*[:#]?$', caseSensitive: false).hasMatch(lines[i]) && i + 1 < lines.length) {
      final n = RegExp(r'^[A-Za-z0-9]{6,}$').firstMatch(lines[i + 1].replaceAll(' ', ''));
      if (n != null) reference = n.group(0);
    }
  }

  return ImportedPayment(amountCents: amount, payee: payee, reference: reference, date: _findDate(lines, today));
}

String? _findDate(List<String> lines, String today) {
  String two(int n) => n.toString().padLeft(2, '0');
  for (final l in lines) {
    final iso = RegExp(r'\b(20\d{2})-(\d{2})-(\d{2})\b').firstMatch(l);
    final named = RegExp(r'\b(\d{1,2})\s+([A-Za-z]{3})[a-z]*\.?,?\s+(20\d{2})\b').firstMatch(l);
    final slash = RegExp(r'\b(\d{1,2})[/.-](\d{1,2})[/.-](20\d{2})\b').firstMatch(l);
    String? out;
    if (iso != null) {
      out = '${iso.group(1)}-${iso.group(2)}-${iso.group(3)}';
    } else if (named != null) {
      final mo = _months[named.group(2)!.toLowerCase()];
      if (mo != null) out = '${named.group(3)}-${two(mo)}-${two(int.parse(named.group(1)!))}';
    } else if (slash != null) {
      out = '${slash.group(3)}-${two(int.parse(slash.group(2)!))}-${two(int.parse(slash.group(1)!))}'; // Malaysian day/month/year
    }
    if (out == null) continue;
    final d = DateTime.tryParse(out);
    if (d == null || out.compareTo(today) > 0) continue;
    return out;
  }
  return null;
}

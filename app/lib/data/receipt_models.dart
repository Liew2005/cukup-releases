class ParsedItem {
  ParsedItem(this.name, this.priceCents, {this.qty = 1, int? unitCents}) : unitCents = unitCents ?? priceCents;
  String name;
  int priceCents; // line total, quantity already multiplied
  int qty;
  int unitCents;
}

/// A receipt as read by the server (Gemini) or by the offline parser. Amounts are whole cents.
class ParsedReceipt {
  ParsedReceipt({
    this.merchant,
    this.date,
    required this.items,
    this.taxCents = 0,
    this.serviceCents = 0,
    this.sstCents = 0,
    this.roundingCents = 0,
    this.totalCents,
    this.categoryId,
    this.categorySource,
    required this.confidence,
    this.warnings = const [],
    required this.via,
  });

  String? merchant;
  String? date; // YYYY-MM-DD
  List<ParsedItem> items;
  int taxCents; // service charge + SST together
  int serviceCents; // printed service charge (10%)
  int sstCents; // printed SST / service tax (6%)
  int roundingCents;
  int? totalCents;
  int? categoryId;
  String? categorySource; // rule | ai
  double confidence;
  List<String> warnings;
  String via; // ai | offline
  String? reference; // payment reference from a shared screenshot
  bool isImport = false; // came from a payment screenshot, not a receipt photo

  factory ParsedReceipt.fromServer(Map<String, dynamic> j) => ParsedReceipt(
        merchant: j['merchant'] as String?,
        date: j['date'] as String?,
        items: [
          for (final i in (j['items'] as List<dynamic>? ?? const []))
            ParsedItem((i as Map)['name'] as String, i['price_cents'] as int, qty: (i['qty'] ?? 1) as int, unitCents: i['unit_cents'] as int?),
        ],
        taxCents: (j['tax_cents'] ?? 0) as int,
        serviceCents: (j['service_cents'] ?? 0) as int,
        sstCents: (j['sst_cents'] ?? (j['tax_cents'] ?? 0)) as int,
        roundingCents: (j['rounding_cents'] ?? 0) as int,
        totalCents: j['total_cents'] as int?,
        categoryId: j['category_id'] as int?,
        categorySource: j['category_source'] as String?,
        confidence: (j['confidence'] as num?)?.toDouble() ?? 0.5,
        warnings: [for (final w in (j['warnings'] as List<dynamic>? ?? const [])) '$w'],
        via: 'ai',
      );

  /// Plain-English problems worth showing above the form.
  List<String> hints() {
    final out = <String>[];
    for (final w in warnings) {
      if (w.startsWith('total_mismatch_')) {
        final diff = int.tryParse(w.substring('total_mismatch_'.length)) ?? 0;
        out.add('The items do not add up to the total (RM ${(diff.abs() / 100).toStringAsFixed(2)} off). Check the amounts.');
      } else if (w == 'no_items') {
        out.add('Could not read the items. Check the total.');
      } else if (w == 'total_inferred') {
        out.add('No total found, so it was worked out from the items.');
      } else if (w == 'no_merchant') {
        out.add('Could not read the shop name.');
      } else if (w == 'bad_date' || w == 'date_in_future') {
        out.add('Could not read the date, so today is used.');
      }
    }
    return out;
  }
}

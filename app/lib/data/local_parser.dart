import '../core/time.dart';
import 'receipt_models.dart';

/// Reads receipt text on the phone with plain rules. Used when offline or when the server cannot help.
/// It is deliberately cautious: anything it is unsure about shows up as a low confidence for the user to check.
/// Understands English, Malay and Chinese receipt words.
class LocalReceiptParser {
  static final _priceAtEnd = RegExp(r'^(.*?)\s+(?:RM\s*|MYR\s*)?(-?\d[\d,]*\.\d{2})(?:\s*-)?(?:\s*[A-Za-z]{1,2})?$', caseSensitive: false);
  static final _subtotal = RegExp(r'(sub\s*-?\s*total|小计|小計)', caseSensitive: false);
  static final _total = RegExp(r'(grand\s*total|total\s*(payable|due|amount)?|amount\s*(due|payable)|jumlah|net\s*total|bill\s*total|总计|總計|合计|合計|总额|總額|总数|应付|應付|共计|共計)', caseSensitive: false);
  static final _tax = RegExp(r'(\b(sst|gst|tax|cukai|service\s*charge|svc|s/c)\b|税|稅|服务费|服務費)', caseSensitive: false);
  static final _service = RegExp(r'(service\s*charge|\bsvc\b|s/c|服务费|服務費)', caseSensitive: false);
  // "... 3 11.00 0.00" in front of the line total: quantity, unit price and (optionally) a discount column.
  static final _qtyUnit = RegExp(r'\s(\d{1,3})\s+(\d[\d,]*\.\d{2})(?:\s+\d[\d,]*\.\d{2}){0,2}$');
  static final _rounding = RegExp(r'(round|四舍五入|凑整|湊整|进位|進位)', caseSensitive: false);
  static final _payment = RegExp(
      r'(\b(cash|change|tender|tunai|baki|balance|visa|master|mastercard|debit|credit|card|tng|touch|grab|boost|qr|paid|payment|points?|voucher)\b|现金|現金|找零|找钱|找錢|付款|刷卡|信用卡|电子钱包|電子錢包)',
      caseSensitive: false);
  static final _skipMerchant = RegExp(
      r'(tax\s*invoice|receipt|invoice|welcome|thank|\b(tel|phone|fax|gst|sst|reg|lot)\b|no\.?\s*\d|www\.|http|@|\bjalan\b|\bjln\b|^\d|电话|電話|地址|发票|發票|收据|收據|欢迎|歡迎|谢谢|謝謝)',
      caseSensitive: false);
  static final _hasWord = RegExp(r'[一-鿿]|\p{L}{2}', unicode: true);
  static final _hasMerchantWord = RegExp(r'[一-鿿]{2}|\p{L}{3}', unicode: true);
  static const _months = {'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6, 'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12};

  static int _cents(String s) {
    final v = double.parse(s.replaceAll(',', ''));
    return (v * 100).round();
  }

  static ParsedReceipt parse(String text, {required String today}) {
    final lines = text.split(RegExp(r'[\r\n]+')).map((l) => l.replaceAll(RegExp(r'\s+'), ' ').trim()).where((l) => l.isNotEmpty).toList();
    final warnings = <String>[];

    final items = <ParsedItem>[];
    var tax = 0;
    var service = 0;
    var sst = 0;
    var rounding = 0;
    int? total;

    for (final line in lines) {
      final m = _priceAtEnd.firstMatch(line);
      if (m == null) continue;
      final name = m.group(1)!.trim();
      final cents = _cents(m.group(2)!);
      if (_subtotal.hasMatch(name)) continue;
      if (_rounding.hasMatch(name)) {
        rounding += cents;
      } else if (_total.hasMatch(name) && !_tax.hasMatch(name)) {
        total = cents; // the last one wins: the final amount to pay
      } else if (_tax.hasMatch(name)) {
        tax += cents;
        if (_service.hasMatch(name)) {
          service += cents;
        } else {
          sst += cents;
        }
      } else if (_payment.hasMatch(name)) {
        continue;
      } else {
        var qty = 1;
        var unit = cents;
        final q = _qtyUnit.firstMatch(name);
        if (q != null) {
          final n = int.parse(q.group(1)!);
          final u = _cents(q.group(2)!);
          if (n >= 1 && (n * u - cents).abs() <= n) {
            qty = n;
            unit = u;
          }
        }
        final clean = name.replaceAll(RegExp(r'(\s+\d+(\.\d+)?)+$'), '').replaceAll(RegExp(r'^[\d\s.x*-]+(?=[A-Za-z一-鿿])'), '').trim();
        if (_hasWord.hasMatch(clean)) items.add(ParsedItem(clean, cents, qty: qty, unitCents: unit));
      }
    }

    final itemsSum = items.fold<int>(0, (s, i) => s + i.priceCents);
    var confidence = 0.65;
    if (items.isEmpty) {
      warnings.add('no_items');
      confidence = 0.3;
    } else if (total == null) {
      total = itemsSum + tax + rounding;
      warnings.add('total_inferred');
      confidence = 0.4;
    } else {
      final expected = itemsSum + tax + rounding;
      if ((expected - total).abs() <= 5) {
        confidence = 0.7;
      } else if ((itemsSum - total).abs() <= 5) {
        warnings.add('prices_include_tax');
        confidence = 0.65;
      } else {
        warnings.add('total_mismatch_${total - expected}');
        confidence = 0.35;
      }
    }

    final merchant = _merchant(lines);
    if (merchant == null) {
      warnings.add('no_merchant');
      confidence = (confidence - 0.1).clamp(0.1, 1.0);
    }
    var date = _date(lines);
    if (date == null) {
      warnings.add('bad_date');
    } else if (date.compareTo(addDays(today, 2)) > 0) {
      warnings.add('date_in_future');
      date = null;
    }

    return ParsedReceipt(
      merchant: merchant,
      date: date,
      items: items,
      taxCents: tax,
      serviceCents: service,
      sstCents: sst,
      roundingCents: rounding,
      totalCents: total,
      confidence: double.parse(confidence.toStringAsFixed(2)),
      warnings: warnings,
      via: 'offline',
    );
  }

  static String? _merchant(List<String> lines) {
    for (final l in lines.take(8)) {
      if (!_hasMerchantWord.hasMatch(l)) continue;
      if (_skipMerchant.hasMatch(l)) continue;
      if (_priceAtEnd.hasMatch(l)) continue;
      return l.length > 60 ? l.substring(0, 60) : l;
    }
    return null;
  }

  static String? _date(List<String> lines) {
    final dmy = RegExp(r'(?<!\d)(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{4}|\d{2})(?!\d)');
    final ymdRe = RegExp(r'(?<!\d)(\d{4})[/\-.](\d{1,2})[/\-.](\d{1,2})(?!\d)');
    final cjk = RegExp(r'(\d{4})\s*年\s*(\d{1,2})\s*月\s*(\d{1,2})\s*日?');
    final named = RegExp(r'(?<!\d)(\d{1,2})[ \-]([A-Za-z]{3})[a-z]*[ \-,]*(\d{4})', caseSensitive: false);
    for (final l in lines) {
      final z = cjk.firstMatch(l);
      if (z != null) {
        final r = _make(int.parse(z.group(1)!), int.parse(z.group(2)!), int.parse(z.group(3)!));
        if (r != null) return r;
      }
      final a = ymdRe.firstMatch(l);
      if (a != null) {
        final r = _make(int.parse(a.group(1)!), int.parse(a.group(2)!), int.parse(a.group(3)!));
        if (r != null) return r;
      }
      final b = dmy.firstMatch(l);
      if (b != null) {
        var y = int.parse(b.group(3)!);
        if (y < 100) y += 2000;
        final r = _make(y, int.parse(b.group(2)!), int.parse(b.group(1)!)); // Malaysia writes day first
        if (r != null) return r;
      }
      final c = named.firstMatch(l);
      if (c != null) {
        final mo = _months[c.group(2)!.toLowerCase()];
        if (mo != null) {
          final r = _make(int.parse(c.group(3)!), mo, int.parse(c.group(1)!));
          if (r != null) return r;
        }
      }
    }
    return null;
  }

  static String? _make(int y, int m, int d) {
    if (y < 2000 || y > 2100 || m < 1 || m > 12 || d < 1 || d > 31) return null;
    final dt = DateTime.utc(y, m, d);
    return dt.month == m && dt.day == d ? ymd(dt) : null;
  }
}

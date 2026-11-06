import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import '../core/time.dart';
import '../data/db.dart';
import '../data/providers.dart';
import '../theme/theme.dart';
import 'export_action.dart';
import 'widgets.dart';

const _palette = [Color(0xFF0E3B32), Color(0xFFF2B544), Color(0xFF4F8A6F), Color(0xFFB4432B), Color(0xFF8FB8A2), Color(0xFFC98B2B), Color(0xFF5A6B63), Color(0xFFD9A79B)];

enum _Period { week, month, lastMonth, custom }

/// Income and spending for a chosen period: totals, a donut by category, an 8-week trend and the entries behind them.
class InsightsPage extends ConsumerStatefulWidget {
  const InsightsPage({super.key});
  @override
  ConsumerState<InsightsPage> createState() => _InsightsPageState();
}

class _InsightsPageState extends ConsumerState<InsightsPage> {
  _Period _period = _Period.month;
  String _customFrom = todayKL();
  String _customTo = todayKL();
  String _direction = 'spend';
  int? _categoryId;

  (String, String) _range() {
    final today = todayKL();
    switch (_period) {
      case _Period.week:
        return (mondayOf(today), addDays(mondayOf(today), 6));
      case _Period.month:
        return (firstOfMonth(today), addDays(nextFirst(today), -1));
      case _Period.lastMonth:
        final thisFirst = firstOfMonth(today);
        final prevLast = addDays(thisFirst, -1);
        return (firstOfMonth(prevLast), prevLast);
      case _Period.custom:
        return (_customFrom, _customTo);
    }
  }

  Future<void> _pickCustom() async {
    final now = parseYmd(todayKL());
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.utc(now.year - 3),
      lastDate: now,
      initialDateRange: DateTimeRange(start: parseYmd(_customFrom), end: parseYmd(_customTo)),
      builder: (context, child) => Theme(data: Theme.of(context).copyWith(colorScheme: Theme.of(context).colorScheme.copyWith(primary: Brand.forest)), child: child!),
    );
    if (picked != null) {
      setState(() {
        _period = _Period.custom;
        _customFrom = ymd(picked.start);
        _customTo = ymd(picked.end);
        _categoryId = null;
      });
    }
  }

  String _periodLabel(String from, String to) => from == to ? shortDate(from) : '${shortDate(from)} – ${shortDate(to)}';

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(txnsProvider).asData?.value ?? const <Txn>[];
    final cats = ref.watch(categoriesProvider).asData?.value ?? const <Cat>[];
    final cap = ref.watch(capCentsProvider).asData?.value ?? 25000;
    final names = {for (final c in cats) c.id: c.name};
    final (from, to) = _range();
    final inRange = all.where((t) => t.spentAt.compareTo(from) >= 0 && t.spentAt.compareTo(to) <= 0).toList();

    final income = inRange.where((t) => t.direction == 'income').fold<int>(0, (s, t) => s + t.amountCents);
    final spent = inRange.where((t) => t.direction == 'spend').fold<int>(0, (s, t) => s + t.amountCents);
    final net = income - spent;

    final ofDirection = inRange.where((t) => t.direction == _direction).toList();
    final byCat = <int, int>{};
    for (final t in ofDirection) {
      byCat[t.categoryId] = (byCat[t.categoryId] ?? 0) + t.amountCents;
    }
    final slices = byCat.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final total = slices.fold<int>(0, (s, e) => s + e.value);
    final shown = (_categoryId == null ? ofDirection : ofDirection.where((t) => t.categoryId == _categoryId).toList());

    Widget chip(String label, bool on, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text(label),
            selected: on,
            showCheckmark: false,
            onSelected: (_) => onTap(),
            selectedColor: Brand.forest,
            backgroundColor: Brand.card,
            side: const BorderSide(color: Brand.line),
            labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: on ? Brand.paper : Brand.ink),
          ),
        );

    Widget stat(String label, int cents, {Color? color}) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(color: Brand.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: Brand.line)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Brand.muted)),
              const SizedBox(height: 4),
              FittedBox(fit: BoxFit.scaleDown, child: Text(rm(cents), style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: color ?? Brand.ink))),
            ]),
          ),
        );

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Insights', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.8)),
            IconButton(
              icon: const Icon(Icons.ios_share_rounded),
              tooltip: 'Export this period as CSV',
              onPressed: () => exportCsv(context, inRange, names, label: '$from-to-$to'),
            ),
          ]),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              chip('This week', _period == _Period.week, () => setState(() {
                    _period = _Period.week;
                    _categoryId = null;
                  })),
              chip('This month', _period == _Period.month, () => setState(() {
                    _period = _Period.month;
                    _categoryId = null;
                  })),
              chip('Last month', _period == _Period.lastMonth, () => setState(() {
                    _period = _Period.lastMonth;
                    _categoryId = null;
                  })),
              chip(_period == _Period.custom ? _periodLabel(from, to) : 'Custom…', _period == _Period.custom, _pickCustom),
            ]),
          ),
          const SizedBox(height: 4),
          Text(_periodLabel(from, to), style: const TextStyle(fontSize: 13, color: Brand.muted)),
          const SizedBox(height: 12),
          Row(children: [stat('Income', income), const SizedBox(width: 8), stat('Spent', spent), const SizedBox(width: 8), stat('Net', net, color: net < 0 ? Brand.danger : Brand.forest)]),
          const SizedBox(height: 20),
          SegmentedButton<String>(
            segments: const [ButtonSegment(value: 'spend', label: Text('Spent')), ButtonSegment(value: 'income', label: Text('Income'))],
            selected: {_direction},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() {
              _direction = s.first;
              _categoryId = null;
            }),
            style: SegmentedButton.styleFrom(selectedBackgroundColor: Brand.forest, selectedForegroundColor: Brand.paper, minimumSize: const Size.fromHeight(40)),
          ),
          const SizedBox(height: 16),
          if (slices.isEmpty)
            Padding(padding: const EdgeInsets.symmetric(vertical: 30), child: Center(child: Text(_direction == 'spend' ? 'No spending in this period.' : 'No income in this period.', style: const TextStyle(color: Brand.muted))))
          else ...[
            Center(
              child: SizedBox(
                width: 190,
                height: 190,
                child: Stack(alignment: Alignment.center, children: [
                  CustomPaint(size: const Size(190, 190), painter: _DonutPainter([for (var i = 0; i < slices.length; i++) (slices[i].value / total, _palette[i % _palette.length], _categoryId == null || _categoryId == slices[i].key)])),
                  Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_direction == 'spend' ? 'Spent' : 'Income', style: const TextStyle(fontSize: 12, color: Brand.muted, fontWeight: FontWeight.w600)),
                    Text(rm(_categoryId == null ? total : (byCat[_categoryId] ?? 0)), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                  ]),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < slices.length; i++)
              InkWell(
                onTap: () => setState(() => _categoryId = _categoryId == slices[i].key ? null : slices[i].key),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: Opacity(
                    opacity: _categoryId == null || _categoryId == slices[i].key ? 1 : 0.4,
                    child: Row(children: [
                      Container(width: 12, height: 12, decoration: BoxDecoration(color: _palette[i % _palette.length], borderRadius: BorderRadius.circular(4))),
                      const SizedBox(width: 10),
                      Expanded(child: Text(names[slices[i].key] ?? 'Other', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
                      Text('${(slices[i].value * 100 / total).round()}%', style: const TextStyle(fontSize: 13, color: Brand.muted)),
                      const SizedBox(width: 12),
                      Text(rm(slices[i].value), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ),
              ),
          ],
          const SizedBox(height: 22),
          const Text('Last 8 weeks', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('Spending that counts toward the cap, week by week.', style: TextStyle(fontSize: 13, color: Brand.muted)),
          const SizedBox(height: 12),
          _TrendBars(txns: all, capCents: cap),
          const SizedBox(height: 24),
          Text(_categoryId == null ? 'Transactions' : 'Transactions · ${names[_categoryId] ?? ''}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          if (shown.isEmpty)
            const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Text('Nothing here.', style: TextStyle(color: Brand.muted)))
          else
            for (final t in shown.take(200)) TxnTile(txn: t),
          if (shown.length > 200) const Padding(padding: EdgeInsets.only(top: 10), child: Text('Showing the latest 200. Export the period for everything.', style: TextStyle(fontSize: 12, color: Brand.muted))),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.parts);
  final List<(double, Color, bool)> parts; // fraction, colour, highlighted

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 26.0;
    final rect = Offset(stroke / 2, stroke / 2) & Size(size.width - stroke, size.height - stroke);
    var start = -math.pi / 2;
    for (final (fraction, color, on) in parts) {
      final sweep = fraction * 2 * math.pi;
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = on ? color : color.withValues(alpha: 0.25);
      canvas.drawArc(rect, start, math.max(sweep - 0.02, 0.001), false, p);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => true;
}

class _TrendBars extends StatelessWidget {
  const _TrendBars({required this.txns, required this.capCents});
  final List<Txn> txns;
  final int capCents;

  @override
  Widget build(BuildContext context) {
    final thisMonday = mondayOf(todayKL());
    final weeks = [for (var i = 7; i >= 0; i--) addDays(thisMonday, -7 * i)];
    final totals = [
      for (final w in weeks)
        txns.where((t) => t.direction == 'spend' && t.countsTowardCap && t.spentAt.compareTo(w) >= 0 && t.spentAt.compareTo(addDays(w, 6)) <= 0).fold<int>(0, (s, t) => s + t.amountCents),
    ];
    final top = math.max<double>(totals.fold<int>(0, math.max).toDouble(), capCents * 1.15);
    const h = 110.0;
    return Column(children: [
      SizedBox(
        height: h,
        child: CustomPaint(
          painter: _CapLine(top == 0 ? 0 : capCents / top),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (var i = 0; i < weeks.length; i++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Tooltip(
                    message: '${shortDate(weeks[i])}: ${rm(totals[i])}',
                    child: Container(
                      height: totals[i] == 0 ? 3 : (totals[i] / top * h).clamp(3, h).toDouble(),
                      decoration: BoxDecoration(color: totals[i] > capCents ? Brand.amber : (i == weeks.length - 1 ? Brand.forest : Brand.forest.withValues(alpha: 0.55)), borderRadius: BorderRadius.circular(5)),
                    ),
                  ),
                ),
              ),
          ]),
        ),
      ),
      const SizedBox(height: 6),
      Row(children: [for (final w in weeks) Expanded(child: Center(child: Text(shortDate(w).split(' ').first, style: const TextStyle(fontSize: 11, color: Brand.muted))))]),
      const SizedBox(height: 4),
      Align(alignment: Alignment.centerLeft, child: Text('Dashed line = your ${rm(capCents)} cap. Amber bars went over it. Labels are the Monday of each week.', style: const TextStyle(fontSize: 12, color: Brand.muted))),
    ]);
  }
}

class _CapLine extends CustomPainter {
  _CapLine(this.fraction);
  final double fraction;
  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height * (1 - fraction);
    final p = Paint()
      ..color = Brand.ink.withValues(alpha: 0.5)
      ..strokeWidth = 1.2;
    for (double x = 0; x < size.width; x += 8) {
      canvas.drawLine(Offset(x, y), Offset(x + 4, y), p);
    }
  }

  @override
  bool shouldRepaint(_CapLine old) => old.fraction != fraction;
}

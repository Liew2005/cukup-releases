import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/time.dart';
import '../theme/theme.dart';

/// Seven bars, Monday to Sunday, with a dashed line at the daily pace (cap / 7).
class WeekBars extends StatelessWidget {
  const WeekBars({super.key, required this.daily, required this.capCents, required this.today});
  final Map<String, int> daily;
  final int capCents;
  final String today;

  @override
  Widget build(BuildContext context) {
    final monday = mondayOf(today);
    final days = [for (var i = 0; i < 7; i++) addDays(monday, i)];
    final pace = capCents / 7;
    final values = [for (final d in days) daily[d] ?? 0];
    final top = [...values, pace * 1.25].reduce((a, b) => a > b ? a : b).toDouble();
    const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    const chartH = 96.0;

    return Column(children: [
      SizedBox(
        height: chartH,
        child: CustomPaint(
          painter: _PacePainter(top == 0 ? 0 : pace / top),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: Tooltip(
                    message: '${shortDate(days[i])}: ${rm(values[i])}',
                    child: Container(
                      height: values[i] == 0 ? 3 : (values[i] / top * chartH).clamp(3, chartH).toDouble(),
                      decoration: BoxDecoration(
                        color: days[i].compareTo(today) > 0
                            ? Brand.line
                            : values[i] > pace
                                ? Brand.amber
                                : (days[i] == today ? Brand.forest : Brand.forest.withValues(alpha: 0.55)),
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ),
                ),
              ),
          ]),
        ),
      ),
      const SizedBox(height: 6),
      Row(children: [
        for (var i = 0; i < 7; i++)
          Expanded(child: Center(child: Text(labels[i], style: TextStyle(fontSize: 12, fontWeight: days[i] == today ? FontWeight.w800 : FontWeight.w600, color: days[i] == today ? Brand.ink : Brand.muted)))),
      ]),
      const SizedBox(height: 6),
      Align(alignment: Alignment.centerLeft, child: Text('Dashed line = ${rm(pace.round())} a day to stay under the cap', style: const TextStyle(fontSize: 12, color: Brand.muted))),
    ]);
  }
}

class _PacePainter extends CustomPainter {
  _PacePainter(this.fraction);
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
  bool shouldRepaint(_PacePainter old) => old.fraction != fraction;
}

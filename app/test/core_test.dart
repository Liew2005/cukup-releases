import 'package:flutter_test/flutter_test.dart';
import 'package:cukup/core/format.dart';
import 'package:cukup/core/time.dart';

void main() {
  test('parseCents accepts clean amounts and rejects junk', () {
    expect(parseCents('12'), 1200);
    expect(parseCents('12.5'), 1250);
    expect(parseCents('RM 1,234.50'), 123450);
    expect(parseCents('.99'), 99);
    expect(parseCents('1.234'), isNull);
    expect(parseCents('1.2.3'), isNull);
    expect(parseCents(''), isNull);
    expect(parseCents('abc'), isNull);
  });

  test('rm formats ringgit', () {
    expect(rm(21150), 'RM 211.50');
    expect(rm(123456), 'RM 1,234.56');
    expect(rm(-500), '-RM 5.00');
    expect(rm(500, plus: true), '+RM 5.00');
  });

  test('week maths matches the server (Monday start, Sunday end)', () {
    expect(mondayOf('2026-11-04'), '2026-11-02'); // Wednesday
    expect(mondayOf('2026-11-08'), '2026-11-02'); // Sunday belongs to the same week
    expect(mondayOf('2026-11-09'), '2026-11-09');
    expect(addDays('2026-11-30', 1), '2026-12-01');
    expect(daysToWeekEnd('2026-11-04'), 4);
    expect(daysToWeekEnd('2026-11-08'), 0);
  });

  test('nowIso has millisecond precision and a Z', () {
    expect(nowIso(), matches(RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$')));
  });
}

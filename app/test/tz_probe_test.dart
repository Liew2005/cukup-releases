import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Regression: notifications never started because the bundled timezone data has no Asia/Kuala_Lumpur,
/// so initialisation threw and every reminder silently failed.
void main() {
  test('the zone the notification service uses exists and is UTC+8', () {
    tzdata.initializeTimeZones();
    final loc = tz.getLocation('Asia/Singapore'); // must match NotificationService.init
    expect(tz.TZDateTime(loc, 2026, 11, 6, 21).timeZoneOffset, const Duration(hours: 8));
    expect(tz.TZDateTime(loc, 2026, 7, 1, 21).timeZoneOffset, const Duration(hours: 8)); // no daylight saving
  });

  test('Asia/Kuala_Lumpur is not available, so it must not be used', () {
    tzdata.initializeTimeZones();
    expect(() => tz.getLocation('Asia/Kuala_Lumpur'), throwsA(isA<tz.LocationNotFoundException>()));
  });
}

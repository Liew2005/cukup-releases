import 'package:drift/drift.dart' show Variable;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/format.dart';
import '../core/time.dart';
import 'carry.dart';
import 'db.dart';

/// Everything is scheduled on the phone, so reminders work offline and cost nothing.
/// [refresh] rebuilds the schedule from the data; call it whenever bills or spending change.
class NotificationService {
  NotificationService(this._db);
  final AppDatabase _db;
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _weeklyId = 1;
  static const _nudgeId = 2;
  static const _testId = 3;
  static const _monthlyId = 4;
  static const _dailyId = 5;
  static const _billBaseId = 100;
  static const _billOffsets = [3, 1, 0]; // days before the due date

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'cukup_reminders',
      'Reminders',
      channelDescription: 'Bill due dates, cap warnings and your weekly summary',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  Future<void> init() async {
    tzdata.initializeTimeZones();
    // The bundled timezone data has no Asia/Kuala_Lumpur (it became a link to Singapore). Same clock, UTC+8, no daylight saving.
    tz.setLocalLocation(tz.getLocation('Asia/Singapore'));
    await _plugin.initialize(settings: const InitializationSettings(android: AndroidInitializationSettings('ic_stat_cukup')));
    _ready = true;
  }

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  Future<bool> enabled() async => (await _android?.areNotificationsEnabled()) ?? false;

  /// Shows the Android 13+ permission prompt. Returns whether notifications are allowed.
  Future<bool> requestPermission() async => (await _android?.requestNotificationsPermission()) ?? false;

  /// Shows a test notification. Returns null on success, or a plain-English reason it did not work.
  Future<String?> showTest() async {
    try {
      if (!_ready) await init(); // it failed or has not finished: try again and show the real error if it still fails
      await _plugin.show(id: _testId, title: 'Cukup test', body: 'Reminders are working on this phone.', notificationDetails: _details);
      return null;
    } catch (e) {
      return 'Reminders could not start: $e';
    }
  }

  tz.TZDateTime _at9(String ymdDate, [int hour = 9]) {
    final d = parseYmd(ymdDate);
    return tz.TZDateTime(tz.local, d.year, d.month, d.day, hour);
  }

  /// A reminder on the 1st of every month, 10am, to save a CSV backup of last month.
  Future<void> _scheduleMonthly() async {
    final now = tz.TZDateTime.now(tz.local);
    final today = todayKL();
    var fire = _at9(firstOfMonth(today), 10);
    if (!fire.isAfter(now)) fire = _at9(nextFirst(today), 10);
    await _plugin.zonedSchedule(
      id: _monthlyId,
      title: 'Monthly export',
      body: 'It is the 1st. Save last month as a CSV: Settings, then Export everything.',
      scheduledDate: fire,
      notificationDetails: _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.dayOfMonthAndTime,
    );
  }

  /// Rebuilds bill reminders and the weekly summary, then checks the cap nudge.
  Future<void> refresh() async {
    if (!_ready) return;
    await _plugin.cancelAllPendingNotifications();
    if (await isOn('bills')) await _scheduleBills();
    if (await isOn('weekly')) await _scheduleWeekly();
    await _scheduleMonthly();
    if (await isOn('cap')) await _capNudge();
    if (await isOn('daily')) await _scheduleDaily();
  }

  Future<void> _scheduleBills() async {
    final now = tz.TZDateTime.now(tz.local);
    final today = todayKL();
    var next = _billBaseId;
    for (final b in await _db.getBills()) {
      if (b.paidAt != null) continue;
      final days = daysBetween(today, b.dueDate);
      final amount = rm(b.amountCents);
      String when(int offset) => offset == 0 ? 'is due today' : offset == 1 ? 'is due tomorrow' : 'is due in $offset days (${shortDate(b.dueDate)})';
      String key(int offset) => 'meta.n.${b.id}.${b.dueDate}.$offset';

      if (days < 0) {
        // Overdue: say so once.
        final k = 'meta.n.${b.id}.${b.dueDate}.over';
        if (await _db.getKv(k) == null) {
          await _db.setKv(k, '1');
          await _plugin.show(id: next++, title: '${b.name} is overdue', body: '$amount was due ${shortDate(b.dueDate)}. Mark it paid once you have.', notificationDetails: _details);
        }
        continue;
      }

      int? latestPassed;
      for (final offset in _billOffsets) {
        final fire = _at9(addDays(b.dueDate, -offset));
        if (fire.isAfter(now)) {
          await _plugin.zonedSchedule(
            id: next++,
            title: '${b.name} $amount',
            body: 'Your ${b.name} bill ${when(offset)}.',
            scheduledDate: fire,
            notificationDetails: _details,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          );
          await _db.setKv(key(offset), '1');
        } else {
          latestPassed = offset; // offsets run 3,1,0 so the last passed one is the closest to the due date
        }
      }
      // A bill added after its reminder time already passed (like one due tomorrow, added in the afternoon):
      // remind once right away instead of staying silent.
      if (latestPassed != null && await _db.getKv(key(latestPassed)) == null) {
        for (final o in _billOffsets) {
          if (!_at9(addDays(b.dueDate, -o)).isAfter(now)) await _db.setKv(key(o), '1');
        }
        await _plugin.show(id: next++, title: '${b.name} $amount', body: 'Your ${b.name} bill ${when(days)}.', notificationDetails: _details);
      }
    }
  }

  Future<void> _scheduleWeekly() async {
    final now = tz.TZDateTime.now(tz.local);
    final today = todayKL();
    var sunday = addDays(mondayOf(today), 6);
    var fire = tz.TZDateTime(tz.local, parseYmd(sunday).year, parseYmd(sunday).month, parseYmd(sunday).day, 20);
    var thisWeek = true;
    if (!fire.isAfter(now)) {
      sunday = addDays(sunday, 7);
      final d = parseYmd(sunday);
      fire = tz.TZDateTime(tz.local, d.year, d.month, d.day, 20);
      thisWeek = false;
    }
    final String body;
    if (thisWeek) {
      final spent = await _weekSpent();
      final cap = await _cap();
      final left = cap - spent;
      body = left >= 0 ? '${rm(spent)} of ${rm(cap)} spent this week. ${rm(left)} left.' : '${rm(spent)} spent, ${rm(-left)} over your ${rm(cap)} cap.';
    } else {
      body = 'Open Cukup to see how your week went.';
    }
    await _plugin.zonedSchedule(
      id: _weeklyId,
      title: 'Your week in Cukup',
      body: body,
      scheduledDate: fire,
      notificationDetails: _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  /// Each kind of reminder can be switched off: bills, daily, weekly, cap. All start on.
  Future<bool> isOn(String kind) async => (await _db.getKv('setting.n_$kind')) != '0';

  Future<void> setOn(String kind, bool on) async {
    await _db.setKv('setting.n_$kind', on ? '1' : '0');
    await refresh();
  }

  Future<bool> _loggedOn(String day) async {
    final rows = await _db.customSelect('SELECT COUNT(*) AS c FROM txns WHERE deleted_at IS NULL AND spent_at = ?1', variables: [Variable.withString(day)]).get();
    return rows.first.read<int>('c') > 0;
  }

  /// 9pm nudge, only on a day with nothing logged. It is a single notification for the next
  /// evening that qualifies; every save reschedules it, so logging anything cancels it.
  Future<void> _scheduleDaily() async {
    final now = tz.TZDateTime.now(tz.local);
    var day = todayKL();
    if (!_at9(day, 21).isAfter(now) || await _loggedOn(day) || await _db.getKv('meta.nudge_day') == day) day = addDays(day, 1);
    // Sunday evening already has the weekly summary.
    if (parseYmd(day).weekday == DateTime.sunday && await isOn('weekly')) day = addDays(day, 1);
    await _plugin.zonedSchedule(
      id: _dailyId,
      title: 'Anything to log today?',
      body: 'Nothing logged yet today. Tap to add it in a few seconds.',
      scheduledDate: _at9(day, 21),
      notificationDetails: _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  Future<int> _weekSpent() async {
    final monday = mondayOf(todayKL());
    final rows = await _db
        .customSelect(
          "SELECT COALESCE(SUM(amount_cents), 0) AS c FROM txns WHERE deleted_at IS NULL AND direction = 'spend' AND counts_toward_cap = 1 AND spent_at BETWEEN ?1 AND ?2",
          variables: [Variable.withString(monday), Variable.withString(addDays(monday, 6))],
        )
        .get();
    return rows.first.read<int>('c');
  }

  /// This week's available cap, with earlier overspending carried in.
  Future<int> _cap() async => (await loadCapInfo(_db)).effective;

  /// One warning at 80% of the weekly cap and one when it is passed, each at most once per week.
  Future<void> _capNudge() async {
    final cap = await _cap();
    if (cap <= 0) return;
    final spent = await _weekSpent();
    final level = spent >= cap ? 100 : (spent * 100 >= cap * 80 ? 80 : 0);
    if (level == 0) return;
    final monday = mondayOf(todayKL());
    final shown = await _db.getKv('meta.cap_nudge') ?? '';
    final parts = shown.split(':');
    final shownLevel = parts.length == 2 && parts[0] == monday ? int.tryParse(parts[1]) ?? 0 : 0;
    if (shownLevel >= level) return;
    if (await _db.getKv('meta.nudge_day') == todayKL()) return; // never more than one nudge a day
    await _db.setKv('meta.cap_nudge', '$monday:$level');
    await _db.setKv('meta.nudge_day', todayKL());
    final left = cap - spent;
    await _plugin.show(
      id: _nudgeId,
      title: level == 100 ? 'You have hit this week\'s cap' : 'You have used 80% of this week\'s cap',
      body: level == 100 ? '${rm(spent)} spent of ${rm(cap)}.' : '${rm(spent)} spent, ${rm(left)} left until ${shortDate(addDays(monday, 6))}.',
      notificationDetails: _details,
    );
  }
}

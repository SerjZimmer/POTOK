// RRuleService — простой сервис работы с RRULE (RFC 5545).
//
// Поддержка (MVP):
// - FREQ=DAILY/WEEKLY/MONTHLY/YEARLY + INTERVAL
// - BYDAY (в weekly) и позиционные BYDAY (1MO, -1SU) в monthly
// - BYMONTHDAY/BYMONTH
// - COUNT/UNTIL, EXDATE
//
// Особенности реализаций:
// - все расчеты в UTC;
// - экспансия выполняется в пределах окна [windowStart, windowEnd),
//   это важно для производительности, особенно для бесконечных серий.

class RRuleService {
  String withUntil(String rrule, DateTime untilUtc) {
    final m = parse(rrule);
    m.remove('COUNT');
    m['UNTIL'] = untilUtc;
    return build(m);
  }
  Map<String, dynamic> parse(String rrule) {
    // Простейший парсер «ключ=значение;...» → Map.
    final parts = rrule.split(';');
    final map = <String, dynamic>{};
    for (final p in parts) {
      final i = p.indexOf('=');
      if (i <= 0) continue;
      final k = p.substring(0, i).toUpperCase();
      final v = p.substring(i + 1);
      switch (k) {
        case 'FREQ':
          map['FREQ'] = v.toUpperCase();
          break;
        case 'INTERVAL':
          map['INTERVAL'] = int.tryParse(v) ?? 1;
          break;
        case 'COUNT':
          map['COUNT'] = int.tryParse(v);
          break;
        case 'UNTIL':
          map['UNTIL'] = _parseDateTime(v);
          break;
        case 'BYDAY':
          map['BYDAY'] = v.split(',').map((e) => e.toUpperCase()).toList();
          break;
        case 'BYMONTHDAY':
          map['BYMONTHDAY'] = v.split(',').map((e) => int.tryParse(e) ?? 0).toList();
          break;
        case 'BYMONTH':
          map['BYMONTH'] = v.split(',').map((e) => int.tryParse(e) ?? 0).toList();
          break;
        case 'WKST':
          map['WKST'] = v.toUpperCase();
          break;
        default:
          map[k] = v;
      }
    }
    map['INTERVAL'] ??= 1;
    return map;
  }

  String build(Map<String, dynamic> spec) {
    // Обратно собираем RRULE из разобранного словаря.
    final buf = <String>[];
    void add(String k, String v) { buf.add('$k=$v'); }
    add('FREQ', (spec['FREQ'] as String).toUpperCase());
    if ((spec['INTERVAL'] ?? 1) != 1) add('INTERVAL', '${spec['INTERVAL']}');
    if (spec['COUNT'] != null) add('COUNT', '${spec['COUNT']}');
    if (spec['UNTIL'] != null) add('UNTIL', _formatDateTime(spec['UNTIL'] as DateTime));
    if (spec['BYDAY'] != null) add('BYDAY', (spec['BYDAY'] as List).join(','));
    if (spec['BYMONTHDAY'] != null) add('BYMONTHDAY', (spec['BYMONTHDAY'] as List).join(','));
    if (spec['BYMONTH'] != null) add('BYMONTH', (spec['BYMONTH'] as List).join(','));
    if (spec['WKST'] != null) add('WKST', spec['WKST']);
    return buf.join(';');
  }

  // Expand occurrences in [windowStartUtc, windowEndUtc)
  List<DateTime> expand({
    required DateTime dtStartUtc,
    required String rrule,
    required DateTime windowStartUtc,
    required DateTime windowEndUtc,
    List<DateTime>? exdates,
  }) {
    final rule = parse(rrule);
    final freq = (rule['FREQ'] as String?) ?? 'DAILY';
    final interval = (rule['INTERVAL'] as int?) ?? 1;
    final until = rule['UNTIL'] as DateTime?;
    final count = rule['COUNT'] as int?;
    final byday = (rule['BYDAY'] as List?)?.cast<String>();
    final bymonthday = (rule['BYMONTHDAY'] as List?)?.cast<int>();
    final bymonth = (rule['BYMONTH'] as List?)?.cast<int>();

    final ex = (exdates ?? const <DateTime>[]).map((e) => _dateKey(e)).toSet();
    final out = <DateTime>[];
    DateTime cursor = dtStartUtc;

    bool inWindow(DateTime d) => !d.isBefore(windowStartUtc) && d.isBefore(windowEndUtc);
    bool beforeEnd(DateTime d) {
      if (until != null && d.isAfter(until)) return false;
      if (count != null && out.length >= count) return false;
      return true;
    }

    switch (freq) {
      case 'DAILY':
        cursor = _alignDaily(dtStartUtc, interval, windowStartUtc);
        while (beforeEnd(cursor) && cursor.isBefore(windowEndUtc)) {
          if (!cursor.isBefore(dtStartUtc) && !ex.contains(_dateKey(cursor))) out.add(cursor);
          cursor = cursor.add(Duration(days: interval));
        }
        break;
      case 'WEEKLY':
        final weekdays = (byday ?? [_weekdayToCode(dtStartUtc.weekday)]).map(_codeToWeekday).toList();
        // align to week start containing windowStartUtc
        DateTime weekStart = _weekStart(dtStartUtc, windowStartUtc);
        while (beforeEnd(weekStart) && weekStart.isBefore(windowEndUtc)) {
          for (final wd in weekdays) {
            final d = DateTime.utc(weekStart.year, weekStart.month, weekStart.day).add(Duration(days: wd - 1));
            final occ = DateTime.utc(d.year, d.month, d.day, dtStartUtc.hour, dtStartUtc.minute);
            if (!occ.isBefore(dtStartUtc) && inWindow(occ) && !ex.contains(_dateKey(occ))) out.add(occ);
          }
          weekStart = weekStart.add(Duration(days: 7 * interval));
        }
        out.sort();
        if (count != null && out.length > count) out.removeRange(count, out.length);
        break;
      case 'MONTHLY':
        int day = (bymonthday != null && bymonthday.isNotEmpty) ? bymonthday.first : dtStartUtc.day;
        final bydayPos = _parseByDayPos(rule['BYDAY']);
        DateTime m = DateTime.utc(windowStartUtc.year, windowStartUtc.month, 1);
        // step months by interval
        while (beforeEnd(m)) {
          DateTime candidate;
          if (bydayPos != null) {
            final wd = bydayPos.$2; // 1..7
            final n = bydayPos.$1; // e.g., 1..4 or -1
            final d = _nthWeekdayOfMonth(m.year, m.month, wd, n);
            candidate = DateTime.utc(m.year, m.month, d, dtStartUtc.hour, dtStartUtc.minute);
          } else {
            candidate = DateTime.utc(m.year, m.month, day, dtStartUtc.hour, dtStartUtc.minute);
          }
          if (!candidate.isBefore(dtStartUtc) && inWindow(candidate) && candidate.month == m.month && !ex.contains(_dateKey(candidate))) out.add(candidate);
          m = DateTime.utc(m.year, m.month + interval, 1);
          if (m.isAfter(windowEndUtc)) break;
        }
        break;
      case 'YEARLY':
        final month = (bymonth != null && bymonth.isNotEmpty) ? bymonth.first : dtStartUtc.month;
        final day = (bymonthday != null && bymonthday.isNotEmpty) ? bymonthday.first : dtStartUtc.day;
        int year = windowStartUtc.year;
        while (true) {
          final candidate = DateTime.utc(year, month, day, dtStartUtc.hour, dtStartUtc.minute);
          if (!beforeEnd(candidate) || candidate.isAfter(windowEndUtc)) break;
          if (!candidate.isBefore(dtStartUtc) && inWindow(candidate) && !ex.contains(_dateKey(candidate))) out.add(candidate);
          year += interval;
        }
        break;
      default:
        // unsupported freq -> single occurrence if in window
        if (inWindow(dtStartUtc) && !ex.contains(_dateKey(dtStartUtc))) out.add(dtStartUtc);
    }

    return out;
  }

  // Helpers
  static DateTime _parseDateTime(String s) {
    // Поддерживаем базовые форматы: YYYYMMDD и YYYYMMDDTHHMMSSZ
    // Support basic forms: YYYYMMDD or YYYYMMDDTHHMMSSZ
    if (s.endsWith('Z')) {
      final yyyy = int.parse(s.substring(0, 4));
      final mm = int.parse(s.substring(4, 6));
      final dd = int.parse(s.substring(6, 8));
      final hh = int.parse(s.substring(9, 11));
      final mi = int.parse(s.substring(11, 13));
      final ss = int.parse(s.substring(13, 15));
      return DateTime.utc(yyyy, mm, dd, hh, mi, ss);
    } else {
      final yyyy = int.parse(s.substring(0, 4));
      final mm = int.parse(s.substring(4, 6));
      final dd = int.parse(s.substring(6, 8));
      return DateTime.utc(yyyy, mm, dd);
    }
  }

  static String _formatDateTime(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}${two(d.month)}${two(d.day)}T${two(d.hour)}${two(d.minute)}${two(d.second)}Z';
  }

  static String _dateKey(DateTime d) => '${d.year}-${d.month}-${d.day}';
  static String _weekdayToCode(int weekday) => const ['MO','TU','WE','TH','FR','SA','SU'][weekday - 1];
  static int _codeToWeekday(String code) => const {'MO':1,'TU':2,'WE':3,'TH':4,'FR':5,'SA':6,'SU':7}[code] ?? 1;

  static DateTime _alignDaily(DateTime start, int interval, DateTime windowStart) {
    if (!windowStart.isAfter(start)) return start;
    final diffDays = windowStart.difference(DateTime.utc(start.year, start.month, start.day)).inDays;
    final steps = (diffDays ~/ interval);
    final candidate = DateTime.utc(start.year, start.month, start.day + steps * interval, start.hour, start.minute);
    if (candidate.isBefore(windowStart)) {
      return candidate.add(Duration(days: interval));
    }
    return candidate;
  }

  static DateTime _weekStart(DateTime dtStart, DateTime windowStart) {
    // Monday as start of week
    DateTime anchor = DateTime.utc(windowStart.year, windowStart.month, windowStart.day);
    final delta = (anchor.weekday + 6) % 7; // 0..6 (Mon=0)
    return anchor.subtract(Duration(days: delta));
  }

  // Return (n, weekday) if BYDAY like 1MO,-1SU present; otherwise null
  (int,int)? _parseByDayPos(dynamic bydayField) {
    if (bydayField == null) return null;
    final list = (bydayField as List).cast<String>();
    if (list.isEmpty) return null;
    final m = RegExp(r'^([+-]?\d+)?(MO|TU|WE|TH|FR|SA|SU)$');
    for (final item in list) {
      final match = m.firstMatch(item);
      if (match != null && match.group(1) != null) {
        final n = int.tryParse(match.group(1)!);
        final wd = _codeToWeekday(match.group(2)!);
        if (n != null) return (n, wd);
      }
    }
    return null;
  }

  static int _daysInMonth(int year, int month) {
    final next = month == 12 ? DateTime(year + 1, 1, 1) : DateTime(year, month + 1, 1);
    return next.subtract(const Duration(days: 1)).day;
  }

  static int _nthWeekdayOfMonth(int year, int month, int weekday, int n) {
    final dim = _daysInMonth(year, month);
    if (n > 0) {
      int count = 0;
      for (int d = 1; d <= dim; d++) {
        if (DateTime(year, month, d).weekday == weekday) {
          count++;
          if (count == n) return d;
        }
      }
      return dim; // fallback
    } else {
      int count = 0;
      for (int d = dim; d >= 1; d--) {
        if (DateTime(year, month, d).weekday == weekday) {
          count++;
          if (count == -n) return d;
        }
      }
      return 1;
    }
  }
}

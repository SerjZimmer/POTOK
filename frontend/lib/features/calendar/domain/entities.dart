class CalendarEntity {
  final String uid;
  final String name;
  final String colorHex;
  final bool isVisible;
  final String tzidDefault;

  CalendarEntity({
    required this.uid,
    required this.name,
    required this.colorHex,
    this.isVisible = true,
    this.tzidDefault = 'UTC',
  });

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'name': name,
        'colorHex': colorHex,
        'isVisible': isVisible,
        'tzidDefault': tzidDefault,
      };

  static CalendarEntity fromJson(Map<String, dynamic> j) => CalendarEntity(
        uid: j['uid'] as String,
        name: j['name'] as String,
        colorHex: j['colorHex'] as String,
        isVisible: (j['isVisible'] as bool?) ?? true,
        tzidDefault: (j['tzidDefault'] as String?) ?? 'UTC',
      );
}

class EventEntity {
  final String uid;
  final String calendarUid;
  final String title;
  final String? description;
  final String? location;
  final DateTime startUtc;
  final DateTime endUtc;
  final bool isAllDay;
  final String tzid;
  final String? recurrenceRule; // raw RRULE
  final List<DateTime>? exdates;
  final String? parentUid; // for overrides (single instance)
  final String? recurrenceId; // RFC 5545 RECURRENCE-ID (UTC)

  EventEntity({
    required this.uid,
    required this.calendarUid,
    required this.title,
    required this.startUtc,
    required this.endUtc,
    this.description,
    this.location,
    this.isAllDay = false,
    this.tzid = 'UTC',
    this.recurrenceRule,
    this.exdates,
    this.parentUid,
    this.recurrenceId,
  });

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'calendarUid': calendarUid,
        'title': title,
        'description': description,
        'location': location,
        'startUtc': startUtc.toIso8601String(),
        'endUtc': endUtc.toIso8601String(),
        'isAllDay': isAllDay,
        'tzid': tzid,
        'recurrenceRule': recurrenceRule,
        'exdates': exdates?.map((e) => e.toIso8601String()).toList(),
        'parentUid': parentUid,
        'recurrenceId': recurrenceId,
      };

  static EventEntity fromJson(Map<String, dynamic> j) => EventEntity(
        uid: j['uid'] as String,
        calendarUid: j['calendarUid'] as String,
        title: j['title'] as String,
        description: j['description'] as String?,
        location: j['location'] as String?,
        startUtc: DateTime.parse(j['startUtc'] as String).toUtc(),
        endUtc: DateTime.parse(j['endUtc'] as String).toUtc(),
        isAllDay: (j['isAllDay'] as bool?) ?? false,
        tzid: (j['tzid'] as String?) ?? 'UTC',
        recurrenceRule: j['recurrenceRule'] as String?,
        exdates: (j['exdates'] as List?)?.map((e) => DateTime.parse(e as String).toUtc()).toList(),
        parentUid: j['parentUid'] as String?,
        recurrenceId: j['recurrenceId'] as String?,
      );
}

// Calendar repository abstraction for offline-first access.
// TODO: Implement with Drift + FTS5 and background isolates.

abstract class CalendarRepository {
  Future<List<CalendarEntity>> listCalendars();
  Future<CalendarEntity> createCalendar(CalendarEntity calendar);
  Future<void> updateCalendar(CalendarEntity calendar);
  Future<void> deleteCalendar(String uid);

  Future<List<EventEntity>> queryEvents({
    List<String>? calendarUids,
    DateTime? timeMin,
    DateTime? timeMax,
    String? query,
    DateTime? updatedMin,
    bool includeDeleted = false,
  });
  Future<EventEntity> upsertEvent(EventEntity event);
  Future<void> deleteEvent(String uid, {DateTime? deletedAt});

  Future<List<ReminderEntity>> getReminders(String eventUid);
  Future<void> setReminders(String eventUid, List<ReminderEntity> reminders);
  Future<void> addReminder(String eventUid, ReminderEntity reminder);
  Future<void> deleteReminder(String eventUid, int reminderId);
}

class CalendarEntity {
  final String uid;
  final String name;
  final String colorHex;
  final bool isVisible;
  final String tzidDefault;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  CalendarEntity({
    required this.uid,
    required this.name,
    required this.colorHex,
    required this.isVisible,
    required this.tzidDefault,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });
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
  final String? recurrenceRule; // RFC 5545 RRULE
  final List<DateTime>? exdates; // Exceptions
  final String? parentUid;
  final String? recurrenceId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  EventEntity({
    required this.uid,
    required this.calendarUid,
    required this.title,
    this.description,
    this.location,
    required this.startUtc,
    required this.endUtc,
    required this.isAllDay,
    required this.tzid,
    this.recurrenceRule,
    this.exdates,
    this.parentUid,
    this.recurrenceId,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });
}

class ReminderEntity {
  final int id;
  final String eventUid;
  final int offsetMinutes;
  final String method; // "notification"

  ReminderEntity({
    required this.id,
    required this.eventUid,
    required this.offsetMinutes,
    this.method = 'notification',
  });
}


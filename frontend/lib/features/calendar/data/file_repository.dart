import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import '../domain/entities.dart';
import '../services/rrule_service.dart';

/// FileCalendarRepository — простое офлайн‑хранилище поверх JSON‑файла.
///
/// Зачем так:
/// - не тянем зависимости (Drift/Isar) на этапе быстрых итераций;
/// - легко посмотреть/почистить данные (файл в HOME);
/// - API спроектирован так, чтобы безболезненно заменить реализацию на Drift.
class FileCalendarRepository {
  final String filePath;
  List<CalendarEntity> _calendars = [];
  List<EventEntity> _events = [];
  bool _loaded = false;

  FileCalendarRepository({String? path}) : filePath = path ?? _defaultPath();

  static String _defaultPath() {
    if (kIsWeb) return 'calendar_store.json';
    try {
      final home = Platform.environment['HOME'];
      if (home != null && home.isNotEmpty) return '$home/.potok_calendar.json';
    } catch (_) {}
    return 'calendar_store.json';
  }

  /// Лениво загружаем данные один раз, при необходимости создаем файл
  /// с дефолтным календарем «Личный».
  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    try {
      final f = File(filePath);
      if (!await f.exists()) {
        _calendars = [CalendarEntity(uid: _uid(), name: 'Личный', colorHex: '#FFC107')];
        _events = [];
        await _persist();
      } else {
        final content = await f.readAsString();
        final j = json.decode(content) as Map<String, dynamic>;
        _calendars = (j['calendars'] as List).map((e) => CalendarEntity.fromJson(e)).toList();
        _events = (j['events'] as List).map((e) => EventEntity.fromJson(e)).toList();
      }
    } catch (e) {
      // reset on failure
      _calendars = [CalendarEntity(uid: _uid(), name: 'Личный', colorHex: '#FFC107')];
      _events = [];
    } finally {
      _loaded = true;
    }
  }

  Future<void> _persist() async {
    final f = File(filePath);
    final data = json.encode({
      'calendars': _calendars.map((e) => e.toJson()).toList(),
      'events': _events.map((e) => e.toJson()).toList(),
    });
    await f.writeAsString(data);
  }

  /// Возвращает список календарей (пока только локальные).
  Future<List<CalendarEntity>> listCalendars() async {
    await _ensureLoaded();
    return List.unmodifiable(_calendars);
  }

  /// Создание события (в том числе повторяющегося). Сохранение на диск синхронно.
  Future<EventEntity> createEvent(EventEntity event) async {
    await _ensureLoaded();
    _events.add(event);
    await _persist();
    return event;
  }

  Future<EventEntity?> getEvent(String uid) async {
    await _ensureLoaded();
    try {
      return _events.firstWhere((e) => e.uid == uid);
    } catch (_) {
      return null;
    }
  }

  Future<void> updateEvent(EventEntity updated) async {
    await _ensureLoaded();
    for (var i = 0; i < _events.length; i++) {
      if (_events[i].uid == updated.uid) {
        _events[i] = updated;
        await _persist();
        return;
      }
    }
  }

  /// Возвращает экземпляры событий, попадающих в [fromUtc, toUtc).
  ///
  /// Повторяющиеся события разворачиваются по окну через RRuleService.
  Future<List<EventEntity>> eventsInRange(DateTime fromUtc, DateTime toUtc) async {
    await _ensureLoaded();
    final rrule = RRuleService();
    final out = <EventEntity>[];

    // Split base events / overrides
    // Override — отдельные записи, которые заменяют одиночные инстансы серии.
    final overrides = _events.where((e) => e.parentUid != null && e.recurrenceId != null).toList();
    final base = _events.where((e) => e.parentUid == null).toList();

    for (final e in base) {
      if (e.recurrenceRule == null || e.recurrenceRule!.isEmpty) {
        if (e.startUtc.isBefore(toUtc) && e.endUtc.isAfter(fromUtc)) out.add(e);
        continue;
      }
      final occ = rrule.expand(
        dtStartUtc: e.startUtc,
        rrule: e.recurrenceRule!,
        windowStartUtc: fromUtc,
        windowEndUtc: toUtc,
        exdates: e.exdates,
      );
      final dur = e.endUtc.difference(e.startUtc);
      for (final o in occ) {
        final rid = o.toIso8601String();
        EventEntity? ov;
        for (final x in overrides) {
          if (x.parentUid == e.uid && x.recurrenceId == rid) { ov = x; break; }
        }
        if (ov != null) {
          out.add(ov);
        } else {
          out.add(EventEntity(
            uid: e.uid,
            calendarUid: e.calendarUid,
            title: e.title,
            description: e.description,
            location: e.location,
            startUtc: o,
            endUtc: o.add(dur),
            isAllDay: e.isAllDay,
            tzid: e.tzid,
            recurrenceRule: e.recurrenceRule, // indicates series occurrence
            exdates: e.exdates,
            parentUid: e.uid,
            recurrenceId: rid,
          ));
        }
      }
    }
    return out;
  }

  // === Операции редактирования/удаления серий и инстансов ===
  Future<void> deleteSingleOccurrence(String parentUid, DateTime recurrenceId) async {
    await _ensureLoaded();
    final i = _events.indexWhere((e) => e.uid == parentUid && e.parentUid == null);
    if (i < 0) return;
    final ex = List<DateTime>.from(_events[i].exdates ?? []);
    ex.add(recurrenceId.toUtc());
    _events[i] = EventEntity(
      uid: _events[i].uid,
      calendarUid: _events[i].calendarUid,
      title: _events[i].title,
      description: _events[i].description,
      location: _events[i].location,
      startUtc: _events[i].startUtc,
      endUtc: _events[i].endUtc,
      isAllDay: _events[i].isAllDay,
      tzid: _events[i].tzid,
      recurrenceRule: _events[i].recurrenceRule,
      exdates: ex,
    );
    await _persist();
  }

  /// Создает или обновляет override для конкретного повторения.
  Future<void> upsertSingleOverride({
    required EventEntity base,
    required DateTime recurrenceId,
    required EventEntity overrideData,
  }) async {
    await _ensureLoaded();
    // ensure exdate
    await deleteSingleOccurrence(base.uid, recurrenceId);
    // upsert override event
    final rid = recurrenceId.toUtc().toIso8601String();
    final idx = _events.indexWhere((e) => e.parentUid == base.uid && e.recurrenceId == rid);
    final ov = EventEntity(
      uid: overrideData.uid,
      calendarUid: overrideData.calendarUid,
      title: overrideData.title,
      description: overrideData.description,
      location: overrideData.location,
      startUtc: overrideData.startUtc,
      endUtc: overrideData.endUtc,
      isAllDay: overrideData.isAllDay,
      tzid: overrideData.tzid,
      recurrenceRule: null,
      exdates: null,
      parentUid: base.uid,
      recurrenceId: rid,
    );
    if (idx >= 0) {
      _events[idx] = ov;
    } else {
      _events.add(ov);
    }
    await _persist();
  }

  /// Удаляет override и убирает соответствующий EXDATE — восстанавливает базовый инстанс.
  Future<void> deleteOverrideAndRestore(String parentUid, DateTime recurrenceId) async {
    await _ensureLoaded();
    final rid = recurrenceId.toUtc().toIso8601String();
    _events.removeWhere((e) => e.parentUid == parentUid && e.recurrenceId == rid);
    // remove exdate from parent
    final i = _events.indexWhere((e) => e.uid == parentUid && e.parentUid == null);
    if (i >= 0) {
      final ex = List<DateTime>.from(_events[i].exdates ?? []);
      ex.removeWhere((d) => d.toUtc().toIso8601String() == rid);
      _events[i] = EventEntity(
        uid: _events[i].uid,
        calendarUid: _events[i].calendarUid,
        title: _events[i].title,
        description: _events[i].description,
        location: _events[i].location,
        startUtc: _events[i].startUtc,
        endUtc: _events[i].endUtc,
        isAllDay: _events[i].isAllDay,
        tzid: _events[i].tzid,
        recurrenceRule: _events[i].recurrenceRule,
        exdates: ex,
      );
    }
    await _persist();
  }

  /// Полное удаление серии (включая все override).
  Future<void> deleteSeries(String parentUid) async {
    await _ensureLoaded();
    _events.removeWhere((e) => e.uid == parentUid || e.parentUid == parentUid);
    await _persist();
  }

  /// Разрезает серию на «до» и «после» указанного инстанса.
  ///
  /// 1) Ставит UNTIL на исходной RRULE (до момента split-1сек).
  /// 2) Удаляет override-инстансы на и после точки разреза.
  /// 3) Опционально создает новую серию (newSeries) начиная с точки разреза.
  Future<void> applyFollowingEdit({
    required String parentUid,
    required DateTime fromUtcAndAfter,
    EventEntity? newSeries, // if null => delete following
  }) async {
    await _ensureLoaded();
    final i = _events.indexWhere((e) => e.uid == parentUid && e.parentUid == null);
    if (i < 0) return;
    final parent = _events[i];
    if ((parent.recurrenceRule ?? '').isEmpty) return;

    // 1) Cut original: set UNTIL to just before fromUtcAndAfter
    final until = fromUtcAndAfter.subtract(const Duration(seconds: 1));
    final r = RRuleService();
    final newRrule = r.withUntil(parent.recurrenceRule!, until);
    _events[i] = EventEntity(
      uid: parent.uid,
      calendarUid: parent.calendarUid,
      title: parent.title,
      description: parent.description,
      location: parent.location,
      startUtc: parent.startUtc,
      endUtc: parent.endUtc,
      isAllDay: parent.isAllDay,
      tzid: parent.tzid,
      recurrenceRule: newRrule,
      exdates: parent.exdates,
    );

    // 2) Remove overrides at or after split point (they belong to following part)
    _events.removeWhere((e) {
      if (e.parentUid != parentUid || e.recurrenceId == null) return false;
      final rid = DateTime.parse(e.recurrenceId!).toUtc();
      return !rid.isBefore(fromUtcAndAfter); // at or after split
    });

    // 3) Optionally add new series starting from split
    if (newSeries != null) {
      _events.add(newSeries);
    }
    await _persist();
  }

  Future<void> deleteEvent(String uid) async {
    await _ensureLoaded();
    _events.removeWhere((e) => e.uid == uid);
    await _persist();
  }

  static String _uid() {
    // random 24-char id
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rnd = Random.secure();
    return List.generate(24, (_) => chars[rnd.nextInt(chars.length)]).join();
  }
}

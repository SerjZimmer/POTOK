import 'package:flutter/material.dart';
import '../data/file_repository.dart';
import '../domain/entities.dart';

/// Редактор события (создание/изменение/удаление).
///
/// Поддерживает выбор области действия при работе с сериями:
/// - только этот инстанс → создается override (RECURRENCE-ID) и EXDATE в базе;
/// - это и все последующие → серия разрезается, создается новая серия;
/// - вся серия → обновляется/удаляется базовая запись.
class EventEditorPage extends StatefulWidget {
  final DateTime? initialDay;
  final FileCalendarRepository repo;
  final EventEntity? event; // if provided -> edit mode (series level)
  const EventEditorPage({super.key, this.initialDay, required this.repo, this.event});

  @override
  State<EventEditorPage> createState() => _EventEditorPageState();
}

class _EventEditorPageState extends State<EventEditorPage> {
  final _form = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  bool _allDay = false;
  late DateTime _start;
  late DateTime _end;
  String? _calendarUid;
  List<CalendarEntity> _calendars = [];
  String _repeat = 'none';
  EventEntity? _editing;

  @override
  void initState() {
    super.initState();
    if (widget.event != null) {
      _editing = widget.event;
      _titleCtrl.text = widget.event!.title;
      _descCtrl.text = widget.event!.description ?? '';
      _allDay = widget.event!.isAllDay;
      _start = widget.event!.startUtc;
      _end = widget.event!.endUtc;
      _repeat = _detectRepeat(widget.event!.recurrenceRule);
    } else {
      final d = widget.initialDay ?? DateTime.now();
      _start = DateTime(d.year, d.month, d.day, 9).toUtc();
      _end = _start.add(const Duration(hours: 1));
    }
    _loadCalendars();
  }

  Future<void> _loadCalendars() async {
    final list = await widget.repo.listCalendars();
    setState(() {
      _calendars = list;
      _calendarUid = list.isNotEmpty ? list.first.uid : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    String df(DateTime d) {
      const months = ['янв','фев','мар','апр','май','июн','июл','авг','сен','окт','ноя','дек'];
      const wk = ['Пн','Вт','Ср','Чт','Пт','Сб','Вс'];
      final ld = d.toLocal();
      final w = wk[(ld.weekday + 6) % 7];
      return '$w, ${ld.day.toString().padLeft(2,'0')} ${months[ld.month-1]} ${ld.year}';
    }
    String tf(DateTime d) {
      final ld = d.toLocal();
      return '${ld.hour.toString().padLeft(2,'0')}:${ld.minute.toString().padLeft(2,'0')}';
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(_editing == null ? 'Событие' : 'Редактирование'),
        actions: [
          if (_editing != null)
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.amber),
              onPressed: _onDeletePressed,
              tooltip: 'Удалить',
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _onSavePressed,
        child: const Icon(Icons.check),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _form,
          child: ListView(
            children: [
              TextFormField(
                controller: _titleCtrl,
                decoration: const InputDecoration(labelText: 'Название'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Введите название' : null,
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                value: _allDay,
                onChanged: (v) => setState(() => _allDay = v),
                title: const Text('Весь день'),
              ),
              ListTile(
                title: const Text('Начало'),
                subtitle: Text('${df(_start)}${_allDay ? '' : ' · ${tf(_start)}'}'),
                onTap: () async { await _pickStart(); },
              ),
              ListTile(
                title: const Text('Окончание'),
                subtitle: Text('${df(_end)}${_allDay ? '' : ' · ${tf(_end)}'}'),
                onTap: () async { await _pickEnd(); },
              ),
              const Divider(),
              DropdownButtonFormField<String>(
                value: _calendarUid,
                items: _calendars.map((c) => DropdownMenuItem(value: c.uid, child: Text(c.name))).toList(),
                onChanged: (v) => setState(() => _calendarUid = v),
                decoration: const InputDecoration(labelText: 'Календарь'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descCtrl,
                decoration: const InputDecoration(labelText: 'Описание'),
                minLines: 2,
                maxLines: 6,
              ),
              const SizedBox(height: 24),
              DropdownButtonFormField<String>(
                value: _repeat,
                items: const [
                  DropdownMenuItem(value: 'none', child: Text('Без повтора')),
                  DropdownMenuItem(value: 'daily', child: Text('Ежедневно')),
                  DropdownMenuItem(value: 'weekly', child: Text('Еженедельно')),
                  DropdownMenuItem(value: 'workdays', child: Text('По рабочим дням')),
                  DropdownMenuItem(value: 'monthly', child: Text('Ежемесячно (по числу)')),
                  DropdownMenuItem(value: 'monthly_wday', child: Text('Ежемесячно (по дню недели)')),
                  DropdownMenuItem(value: 'yearly', child: Text('Ежегодно')),
                ],
                onChanged: (v) => setState(() => _repeat = v ?? 'none'),
                decoration: const InputDecoration(labelText: 'Повторение'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickStart() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _start.toLocal(),
      firstDate: DateTime(1970),
      lastDate: DateTime(2100),
    );
    if (d == null) return;
    if (_allDay) {
      setState(() {
        _start = DateTime(d.year, d.month, d.day).toUtc();
        _end = DateTime(d.year, d.month, d.day).toUtc();
      });
      return;
    }
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_start.toLocal()));
    if (t == null) return;
    final local = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    setState(() {
      _start = local.toUtc();
      if (!_end.isAfter(_start)) _end = _start.add(const Duration(hours: 1));
    });
  }

  Future<void> _pickEnd() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _end.toLocal(),
      firstDate: DateTime(1970),
      lastDate: DateTime(2100),
    );
    if (d == null) return;
    if (_allDay) {
      setState(() { _end = DateTime(d.year, d.month, d.day).toUtc(); });
      return;
    }
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_end.toLocal()));
    if (t == null) return;
    final local = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    setState(() { _end = local.toUtc(); });
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_calendarUid == null) return;
    String _uid() {
      const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
      final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
      int h = ts.hashCode;
      String rand(int n){
        var s='';
        for (var i=0;i<n;i++){ h = 1664525 * h + 1013904223; s += chars[h.abs()%chars.length]; }
        return s;
      }
      return ts + rand(8);
    }
    final e = EventEntity(
      uid: _editing?.uid ?? _uid(),
      calendarUid: _calendarUid!,
      title: _titleCtrl.text.trim(),
      description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      startUtc: _start,
      endUtc: _end.isAfter(_start) ? _end : _start.add(const Duration(hours: 1)),
      isAllDay: _allDay,
      tzid: 'UTC',
      recurrenceRule: _buildRRule(existing: _editing?.recurrenceRule),
      parentUid: _editing?.parentUid,
      recurrenceId: _editing?.recurrenceId,
    );
    if (_editing == null) {
      await widget.repo.createEvent(e);
    } else {
      await widget.repo.updateEvent(e);
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  String? _buildRRule({String? existing}) {
    if (_repeat == 'custom') return existing; // keep as-is
    switch (_repeat) {
      case 'daily':
        return 'FREQ=DAILY;INTERVAL=1;UNTIL=${_until1y()}';
      case 'weekly':
        final wd = ['MO','TU','WE','TH','FR','SA','SU'][_start.toLocal().weekday - 1];
        return 'FREQ=WEEKLY;BYDAY=$wd;UNTIL=${_until1y()}';
      case 'workdays':
        return 'FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR;UNTIL=${_until1y()}';
      case 'monthly':
        return 'FREQ=MONTHLY;BYMONTHDAY=${_start.toLocal().day};UNTIL=${_until1y()}';
      case 'monthly_wday':
        final wd = ['MO','TU','WE','TH','FR','SA','SU'][_start.toLocal().weekday - 1];
        final day = _start.toLocal().day;
        final pos = ((day - 1) ~/ 7) + 1; // 1..5
        return 'FREQ=MONTHLY;BYDAY=${pos.toString()}$wd;UNTIL=${_until1y()}';
      case 'yearly':
        return 'FREQ=YEARLY;BYMONTH=${_start.toLocal().month};BYMONTHDAY=${_start.toLocal().day};UNTIL=${_until1y()}';
      default:
        return null;
    }
  }

  String _until1y() {
    final u = _start.toUtc().add(const Duration(days: 365));
    String two(int v) => v.toString().padLeft(2, '0');
    return '${u.year}${two(u.month)}${two(u.day)}T235959Z';
  }

  Future<void> _onSavePressed() async {
    if (_editing != null) {
      final isOverride = _editing!.parentUid != null && _editing!.recurrenceRule == null;
      final isSeriesOcc = _editing!.parentUid != null && _editing!.recurrenceRule != null;
      final isBaseRecurring = _editing!.parentUid == null && (_editing!.recurrenceRule?.isNotEmpty ?? false);
      if (isOverride) {
        // Simple update of override
        await _save();
        return;
      }
      if (isSeriesOcc || isBaseRecurring) {
        final choice = await showModalBottomSheet<String>(
          context: context,
          builder: (_) => const _ScopeSheet(),
        );
        if (choice == 'this') {
          final baseUid = isSeriesOcc ? _editing!.parentUid! : _editing!.uid;
          final recurrenceId = DateTime.parse(_editing!.recurrenceId ?? _editing!.startUtc.toIso8601String()).toUtc();
          final data = EventEntity(
            uid: _editing!.uid, // temp; will be replaced in repo
            calendarUid: _calendarUid!,
            title: _titleCtrl.text.trim(),
            description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
            startUtc: _start,
            endUtc: _end.isAfter(_start) ? _end : _start.add(const Duration(hours: 1)),
            isAllDay: _allDay,
            tzid: 'UTC',
          );
          final base = await widget.repo.getEvent(baseUid);
          if (base != null) {
            await widget.repo.upsertSingleOverride(base: base, recurrenceId: recurrenceId, overrideData: data);
          }
          if (mounted) Navigator.of(context).pop(true);
          return;
        }
        if (choice == 'following') {
          final baseUid = isSeriesOcc ? _editing!.parentUid! : _editing!.uid;
          final recurrenceId = DateTime.parse(_editing!.recurrenceId ?? _editing!.startUtc.toIso8601String()).toUtc();
          // Create new series starting at recurrenceId with edited fields
          String newUid() {
            const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
            final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
            int h = ts.hashCode; String rand(int n){var s=''; for (var i=0;i<n;i++){ h=1664525*h+1013904223; s+=chars[h.abs()%chars.length]; } return s; }
            return ts+rand(6);
          }
          final newSeries = EventEntity(
            uid: newUid(),
            calendarUid: _calendarUid!,
            title: _titleCtrl.text.trim(),
            description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
            startUtc: _start, // may differ from recurrenceId per user edits
            endUtc: _end.isAfter(_start) ? _end : _start.add(const Duration(hours: 1)),
            isAllDay: _allDay,
            tzid: 'UTC',
            recurrenceRule: _buildRRule(existing: _editing?.recurrenceRule),
          );
          await widget.repo.applyFollowingEdit(parentUid: baseUid, fromUtcAndAfter: recurrenceId, newSeries: newSeries);
          if (mounted) Navigator.of(context).pop(true);
          return;
        }
        if (choice == 'series') {
          // Save on base event
          final baseUid = isSeriesOcc ? _editing!.parentUid! : _editing!.uid;
          _editing = await widget.repo.getEvent(baseUid);
          await _save();
          return;
        }
        return; // cancelled
      }
    }
    await _save();
  }

  Future<void> _onDeletePressed() async {
    if (_editing == null) return;
    final isOverride = _editing!.parentUid != null && _editing!.recurrenceRule == null;
    final isSeriesOcc = _editing!.parentUid != null && _editing!.recurrenceRule != null;
    final isBaseRecurring = _editing!.parentUid == null && (_editing!.recurrenceRule?.isNotEmpty ?? false);
    if (isOverride) {
      await widget.repo.deleteOverrideAndRestore(_editing!.parentUid!, DateTime.parse(_editing!.recurrenceId!));
      if (mounted) Navigator.of(context).pop(true);
      return;
    }
    if (isSeriesOcc || isBaseRecurring) {
      final choice = await showModalBottomSheet<String>(
        context: context,
        builder: (_) => const _ScopeSheet(deleteMode: true),
      );
      if (choice == 'this') {
        final parentUid = isSeriesOcc ? _editing!.parentUid! : _editing!.uid;
        final rid = DateTime.parse(_editing!.recurrenceId ?? _editing!.startUtc.toIso8601String());
        await widget.repo.deleteSingleOccurrence(parentUid, rid);
        if (mounted) Navigator.of(context).pop(true);
        return;
      }
      if (choice == 'following') {
        final parentUid = isSeriesOcc ? _editing!.parentUid! : _editing!.uid;
        final rid = DateTime.parse(_editing!.recurrenceId ?? _editing!.startUtc.toIso8601String());
        await widget.repo.applyFollowingEdit(parentUid: parentUid, fromUtcAndAfter: rid, newSeries: null);
        if (mounted) Navigator.of(context).pop(true);
        return;
      }
      if (choice == 'series') {
        final parentUid = isSeriesOcc ? _editing!.parentUid! : _editing!.uid;
        await widget.repo.deleteSeries(parentUid);
        if (mounted) Navigator.of(context).pop(true);
        return;
      }
      return;
    }
    // Non-recurring
    await widget.repo.deleteEvent(_editing!.uid);
    if (mounted) Navigator.of(context).pop(true);
  }
}

class _ScopeSheet extends StatelessWidget {
  final bool deleteMode;
  const _ScopeSheet({this.deleteMode = false});
  @override
  Widget build(BuildContext context) {
    final title = deleteMode ? 'Удалить' : 'Сохранить изменения';
    final onlyThis = deleteMode ? 'Только это событие' : 'Только это повторение';
    final following = deleteMode ? 'Это и все последующие' : 'Это и все последующие';
    final series = deleteMode ? 'Всю серию' : 'Всю серию';
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold))),
          ListTile(
            leading: const Icon(Icons.filter_1, color: Colors.amber),
            title: Text(onlyThis),
            onTap: () => Navigator.of(context).pop('this'),
          ),
          ListTile(
            leading: const Icon(Icons.trending_flat, color: Colors.amber),
            title: Text(following),
            onTap: () => Navigator.of(context).pop('following'),
          ),
          ListTile(
            leading: const Icon(Icons.all_inclusive, color: Colors.amber),
            title: Text(series),
            onTap: () => Navigator.of(context).pop('series'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

String _detectRepeat(String? rrule) {
  if (rrule == null || rrule.isEmpty) return 'none';
  final u = rrule.toUpperCase();
  if (u.startsWith('FREQ=DAILY') && !u.contains('BYDAY=')) return 'daily';
  if (u.startsWith('FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR')) return 'workdays';
  if (u.startsWith('FREQ=WEEKLY;BYDAY=')) return 'weekly';
  if (u.startsWith('FREQ=MONTHLY') && u.contains('BYMONTHDAY=')) return 'monthly';
  if (u.startsWith('FREQ=MONTHLY') && RegExp(r'BYDAY=[+-]?\d+(MO|TU|WE|TH|FR|SA|SU)').hasMatch(u)) return 'monthly_wday';
  if (u.startsWith('FREQ=YEARLY') && u.contains('BYMONTH=') && u.contains('BYMONTHDAY=')) return 'yearly';
  return 'custom';
}

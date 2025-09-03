import 'package:flutter/material.dart';
import '../data/api_repository.dart';
import '../domain/entities.dart';

/// Редактор события (создание/изменение/удаление).
///
/// Поддерживает выбор области действия при работе с сериями:
/// - только этот инстанс → создается override (RECURRENCE-ID) и EXDATE в базе;
/// - это и все последующие → серия разрезается, создается новая серия;
/// - вся серия → обновляется/удаляется базовая запись.
class EventEditorPage extends StatefulWidget {
  final DateTime? initialDay;
  final ApiCalendarRepository repo;
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
  // Ограничение повтора: 'never' | 'until' | 'count'
  String _repeatEndMode = 'until';
  DateTime? _repeatUntil;
  int? _repeatCount;

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
      // Инициализируем ограничения из RRULE (UNTIL/COUNT), если они есть
      final rr = widget.event!.recurrenceRule;
      if (rr != null && rr.isNotEmpty) {
        final m = _parseRRule(rr);
        if (m['UNTIL'] != null && m['UNTIL']!.isNotEmpty) {
          _repeatEndMode = 'until';
          _repeatUntil = _parseRRuleDate(m['UNTIL']!);
        } else if (m['COUNT'] != null && m['COUNT']!.isNotEmpty) {
          _repeatEndMode = 'count';
          _repeatCount = int.tryParse(m['COUNT']!);
        } else {
          _repeatEndMode = 'never';
        }
      }
    } else {
      final d = widget.initialDay ?? DateTime.now();
      _start = DateTime(d.year, d.month, d.day, 9).toUtc();
      _end = _start.add(const Duration(hours: 1));
    }
    _loadCalendars();
  }

  Future<void> _loadCalendars() async {
    try {
      var list = await widget.repo.listCalendars();
      CalendarEntity? created;
      if (list.isEmpty) {
        created = await widget.repo.createCalendar('Личный');
        list = [created];
      }
      setState(() {
        _calendars = list;
        _calendarUid = (created?.uid) ?? (list.isNotEmpty ? list.first.uid : null);
      });
    } catch (_) {
      // В случае ошибки сети оставим список пустым — пользователь увидит, что выбрать нечего
    }
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
              icon: const Icon(Icons.delete_outline, color: Colors.amber),
              onPressed: _onDeletePressed,
              tooltip: 'Удалить',
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _onSavePressed,
        child: const Icon(Icons.check_circle_outline),
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
                items: _calendars.map((c) => DropdownMenuItem(
                  value: c.uid,
                  child: Row(
                    children: [
                      Container(width: 14, height: 14, decoration: BoxDecoration(color: _hexColor(c.colorHex), shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Text(c.name),
                    ],
                  ),
                )).toList(),
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
              if (_repeat != 'none') ...[
                const SizedBox(height: 8),
                const Text('Ограничение повтора', style: TextStyle(fontWeight: FontWeight.w600)),
                RadioListTile<String>(
                  value: 'never', groupValue: _repeatEndMode, onChanged: (v)=>setState(()=>_repeatEndMode=v!),
                  title: const Text('Без окончания'),
                ),
                RadioListTile<String>(
                  value: 'until', groupValue: _repeatEndMode, onChanged: (v)=>setState(()=>_repeatEndMode=v!),
                  title: const Text('До даты'),
                ),
                if (_repeatEndMode=='until')
                  ListTile(
                    title: Text(_repeatUntil==null ? 'Выбрать дату окончания' : 'До: ${df(_repeatUntil!)}'),
                    onTap: () async {
                      final d = await showDatePicker(context: context, initialDate: (_repeatUntil ?? _start).toLocal(), firstDate: DateTime(1970), lastDate: DateTime(2100));
                      if (d!=null) setState(()=> _repeatUntil = DateTime(d.year,d.month,d.day).toUtc());
                    },
                  ),
                RadioListTile<String>(
                  value: 'count', groupValue: _repeatEndMode, onChanged: (v)=>setState(()=>_repeatEndMode=v!),
                  title: const Text('Количество повторов'),
                ),
                if (_repeatEndMode=='count')
                  TextFormField(
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(hintText: 'Например, 10'),
                    initialValue: _repeatCount?.toString(),
                    onChanged: (v){ final n=int.tryParse(v); setState(()=>_repeatCount=n); },
                    validator: (_){ if(_repeat!='none' && _repeatEndMode=='count'){ if((_repeatCount??0)<=0) return 'Введите число > 0'; } return null; },
                  ),
              ],
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
    String endClause() {
      if (_repeatEndMode == 'until' && _repeatUntil != null) {
        final u = _repeatUntil!;
        String two(int v) => v.toString().padLeft(2,'0');
        return ';UNTIL=${u.year}${two(u.month)}${two(u.day)}T235959Z';
      }
      if (_repeatEndMode == 'count' && (_repeatCount ?? 0) > 0) {
        return ';COUNT=${_repeatCount}';
      }
      // по умолчанию ограничим годом, чтобы не разливаться бесконечно
      return ';UNTIL=${_until1y()}';
    }
    switch (_repeat) {
      case 'daily':
        return 'FREQ=DAILY;INTERVAL=1' + endClause();
      case 'weekly':
        final wd = ['MO','TU','WE','TH','FR','SA','SU'][_start.toLocal().weekday - 1];
        return 'FREQ=WEEKLY;BYDAY=$wd' + endClause();
      case 'workdays':
        return 'FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR' + endClause();
      case 'monthly':
        return 'FREQ=MONTHLY;BYMONTHDAY=${_start.toLocal().day}' + endClause();
      case 'monthly_wday':
        final wd = ['MO','TU','WE','TH','FR','SA','SU'][_start.toLocal().weekday - 1];
        final day = _start.toLocal().day;
        final pos = ((day - 1) ~/ 7) + 1; // 1..5
        return 'FREQ=MONTHLY;BYDAY=${pos.toString()}$wd' + endClause();
      case 'yearly':
        return 'FREQ=YEARLY;BYMONTH=${_start.toLocal().month};BYMONTHDAY=${_start.toLocal().day}' + endClause();
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
          await widget.repo.apply(baseUid, action: 'update', scope: 'this', recurrenceId: recurrenceId.toIso8601String(), patch: {
            'title': _titleCtrl.text.trim(),
            if (_descCtrl.text.trim().isNotEmpty) 'description': _descCtrl.text.trim(),
            'startUtc': _start.toUtc().toIso8601String(),
            'endUtc': (_end.isAfter(_start) ? _end : _start.add(const Duration(hours:1))).toUtc().toIso8601String(),
            'isAllDay': _allDay,
            'tzid': 'UTC',
          });
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
          await widget.repo.apply(baseUid, action: 'update', scope: 'following', recurrenceId: recurrenceId.toIso8601String(), patch: {
            'title': newSeries.title,
            if (newSeries.description != null) 'description': newSeries.description,
            'startUtc': newSeries.startUtc.toUtc().toIso8601String(),
            'endUtc': newSeries.endUtc.toUtc().toIso8601String(),
            'isAllDay': newSeries.isAllDay,
            'tzid': newSeries.tzid,
            if (newSeries.recurrenceRule != null) 'recurrenceRule': newSeries.recurrenceRule,
          });
          if (mounted) Navigator.of(context).pop(true);
          return;
        }
        if (choice == 'series') {
          // Сохраняем изменения на базовой серии через apply scope=series
          final baseUid = isSeriesOcc ? _editing!.parentUid! : _editing!.uid;
          await widget.repo.apply(baseUid, action: 'update', scope: 'series', patch: {
            'title': _titleCtrl.text.trim(),
            if (_descCtrl.text.trim().isNotEmpty) 'description': _descCtrl.text.trim(),
            'startUtc': _start.toUtc().toIso8601String(),
            'endUtc': (_end.isAfter(_start) ? _end : _start.add(const Duration(hours:1))).toUtc().toIso8601String(),
            'isAllDay': _allDay,
            'tzid': 'UTC',
            'recurrenceRule': _buildRRule(existing: _editing?.recurrenceRule),
          });
          if (mounted) Navigator.of(context).pop(true);
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
      await widget.repo.apply(_editing!.parentUid!, action: 'delete', scope: 'this', recurrenceId: _editing!.recurrenceId);
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
        await widget.repo.apply(parentUid, action: 'delete', scope: 'this', recurrenceId: rid.toUtc().toIso8601String());
        if (mounted) Navigator.of(context).pop(true);
        return;
      }
      if (choice == 'following') {
        final parentUid = isSeriesOcc ? _editing!.parentUid! : _editing!.uid;
        final rid = DateTime.parse(_editing!.recurrenceId ?? _editing!.startUtc.toIso8601String());
        await widget.repo.apply(parentUid, action: 'delete', scope: 'following', recurrenceId: rid.toUtc().toIso8601String());
        if (mounted) Navigator.of(context).pop(true);
        return;
      }
      if (choice == 'series') {
        final parentUid = isSeriesOcc ? _editing!.parentUid! : _editing!.uid;
        await widget.repo.apply(parentUid, action: 'delete', scope: 'series');
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
            leading: const Icon(Icons.filter_1_outlined, color: Colors.amber),
            title: Text(onlyThis),
            onTap: () => Navigator.of(context).pop('this'),
          ),
          ListTile(
            leading: const Icon(Icons.trending_flat_outlined, color: Colors.amber),
            title: Text(following),
            onTap: () => Navigator.of(context).pop('following'),
          ),
          ListTile(
            leading: const Icon(Icons.all_inclusive_outlined, color: Colors.amber),
            title: Text(series),
            onTap: () => Navigator.of(context).pop('series'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// Хелпер перевода HEX (#RRGGBB или #AARRGGBB) в Color для отображения
Color _hexColor(String hex){
  var h = hex.replaceAll('#','');
  if(h.length==6) h='FF$h';
  return Color(int.parse(h, radix:16));
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

Map<String,String> _parseRRule(String s){
  final map=<String,String>{};
  for(final part in s.split(';')){
    if(part.isEmpty) continue; final kv=part.split('='); if(kv.length==2){ map[kv[0].toUpperCase()]=kv[1]; }
  }
  return map;
}
DateTime? _parseRRuleDate(String s){
  try{
    if(s.endsWith('Z')){
      return DateTime.parse(s.substring(0,4)+'-'+s.substring(4,6)+'-'+s.substring(6,8)+'T'+s.substring(9,11)+':'+s.substring(11,13)+':'+s.substring(13,15)+'Z').toUtc();
    } else { return DateTime.parse(s.substring(0,4)+'-'+s.substring(4,6)+'-'+s.substring(6,8)).toUtc(); }
  }catch(_){return null;}
}

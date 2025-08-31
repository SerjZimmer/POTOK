import 'package:flutter/material.dart';
import '../data/api_repository.dart';
import '../domain/entities.dart';
import 'event_editor.dart';
import 'day_schedule.dart';

/// Экран «Календарь»: офлайн‑первый, поддержка RRULE и нескольких представлений.
/// См. комментарии внизу файла к Month/Day/Week/Agenda‑вью.

enum CalendarView { month, week, threeDay, day, agenda }

class CalendarScreen extends StatefulWidget {
  final ApiCalendarRepository? repo;
  const CalendarScreen({super.key, this.repo});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  CalendarView _view = CalendarView.month;
  DateTime _visibleMonth = _monthStart(DateTime.now());
  DateTime _focusDay = DateTime.now();
  late final ApiCalendarRepository _repo;
  List<EventEntity> _events = [];
  bool _loading = true;
  List<CalendarEntity> _calendars = [];

  @override
  void initState() {
    super.initState();
    _repo = widget.repo ?? ApiCalendarRepository();
    _reloadMonthEvents();
    _reloadCalendars();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titleForView()),
        actions: [
          IconButton(
            tooltip: 'Назад',
            icon: const Icon(Icons.chevron_left, color: Colors.amber),
            onPressed: () async { await _step(-1); },
          ),
          IconButton(
            tooltip: 'Вперёд',
            icon: const Icon(Icons.chevron_right, color: Colors.amber),
            onPressed: () async { await _step(1); },
          ),
          PopupMenuButton<CalendarView>(
            icon: const Icon(Icons.view_agenda, color: Colors.amber),
            onSelected: (v) => _setView(v),
            itemBuilder: (context) => [
              _item('Месяц', CalendarView.month),
              _item('Неделя', CalendarView.week),
              _item('3 дня', CalendarView.threeDay),
              _item('День', CalendarView.day),
              _item('Список', CalendarView.agenda),
            ],
          ),
          IconButton(
            tooltip: 'Календари',
            icon: const Icon(Icons.palette, color: Colors.amber),
            onPressed: () async {
              await showDialog(context: context, builder: (_) => _ManageCalendarsDialog(repo: _repo));
              await _reloadCalendars();
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'calendar-fab',
        onPressed: _createEvent,
        backgroundColor: Colors.amber,
        foregroundColor: Colors.black,
        child: const Icon(Icons.add),
      ),
      body: _buildView(),
    );
  }

  PopupMenuItem<CalendarView> _item(String label, CalendarView view) =>
      PopupMenuItem(value: view, child: Text(label));

  Widget _buildView() {
    switch (_view) {
      case CalendarView.month:
        if (_loading) {
          return const Center(child: CircularProgressIndicator());
        }
        return _MonthView(
          month: _visibleMonth,
          events: _events,
          calendars: _calendars,
          onTapDay: (day) async {
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => DaySchedulePage(day: day, repo: _repo)),
            );
            await _reloadMonthEvents();
          },
          onLongPressDay: (day) async {
            final saved = await Navigator.of(context).push<bool>(
              MaterialPageRoute(builder: (_) => EventEditorPage(initialDay: day, repo: _repo)),
            );
            if (saved == true) await _reloadMonthEvents();
          },
        );
      case CalendarView.week:
        if (_loading) return const Center(child: CircularProgressIndicator());
        return _MultiDayColumns(
          start: _weekStartLocal(_focusDay),
          days: 7,
          events: _events,
          onAdd: (d) => _openEditor(d),
          onEdit: (e) => _openEdit(e),
        );
      case CalendarView.threeDay:
        if (_loading) return const Center(child: CircularProgressIndicator());
        return _MultiDayColumns(
          start: DateTime(_focusDay.year, _focusDay.month, _focusDay.day),
          days: 3,
          events: _events,
          onAdd: (d) => _openEditor(d),
          onEdit: (e) => _openEdit(e),
        );
      case CalendarView.day:
        if (_loading) return const Center(child: CircularProgressIndicator());
        return _DayListView(
          day: _focusDay,
          events: _events,
          onAdd: () => _openEditor(_focusDay),
          onEdit: (e) async {
            final saved = await Navigator.of(context).push<bool>(
              MaterialPageRoute(builder: (_) => EventEditorPage(event: e, repo: _repo)),
            );
            if (saved == true) await _reloadForCurrentView();
          },
        );
      case CalendarView.agenda:
        if (_loading) return const Center(child: CircularProgressIndicator());
        return _AgendaListView(
          start: _focusDay,
          events: _events,
          onAdd: () => _openEditor(_focusDay),
          onEdit: (e) async {
            final saved = await Navigator.of(context).push<bool>(
              MaterialPageRoute(builder: (_) => EventEditorPage(event: e, repo: _repo)),
            );
            if (saved == true) await _reloadForCurrentView();
          },
        );
    }
  }

  void _createEvent() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EventEditorPage(repo: _repo, initialDay: DateTime.now()),
      ),
    ).then((saved) async { if (saved == true) { setState(() { _loading = true; }); await _reloadForCurrentView(); } });
  }

  Future<void> _openEditor(DateTime day) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => EventEditorPage(initialDay: day, repo: _repo)),
    );
    if (saved == true) {
      setState(() { _loading = true; });
      await _reloadForCurrentView();
    }
  }

  Future<void> _openEdit(EventEntity e) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => EventEditorPage(event: e, repo: _repo)),
    );
    if (saved == true) await _reloadForCurrentView();
  }

  static DateTime _monthStart(DateTime d) => DateTime(d.year, d.month, 1);

  static DateTime _addMonths(DateTime d, int delta) {
    final year = d.year + ((d.month + delta - 1) ~/ 12);
    final month = ((d.month + delta - 1) % 12) + 1;
    final day = d.day.clamp(1, _daysInMonth(year, month));
    return DateTime(year, month, day);
  }

  static int _daysInMonth(int year, int month) {
    final beginningNextMonth = month == 12 ? DateTime(year + 1, 1, 1) : DateTime(year, month + 1, 1);
    return beginningNextMonth.subtract(const Duration(days: 1)).day;
  }

  String _titleForMonth(DateTime m) {
    const monthsRu = [
      'Январь','Февраль','Март','Апрель','Май','Июнь',
      'Июль','Август','Сентябрь','Октябрь','Ноябрь','Декабрь'
    ];
    return '${monthsRu[m.month - 1]} ${m.year}';
  }

  Future<void> _reloadMonthEvents() async {
    // Рассчитываем сетку месяца с динамическим числом недель (5 или 6)
    final localFirst = DateTime(_visibleMonth.year, _visibleMonth.month, 1);
    final leading = (localFirst.weekday + 6) % 7; // Mon=0..Sun=6
    final gridStartLocal = localFirst.subtract(Duration(days: leading));
    final daysInMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1, 0).day;
    final totalCells = (((leading + daysInMonth) + 6) ~/ 7) * 7; // 35 или 42
    final gridEndLocal = gridStartLocal.add(Duration(days: totalCells)); // эксклюзивная граница
    final start = gridStartLocal.toUtc();
    final end = gridEndLocal.toUtc(); // expand использует полуинтервал [start,end)
    final res = await _repo.expand(start, end);
    if (!mounted) return;
    setState(() { _events = res; _loading = false; });
  }

  Future<void> _reloadCalendars() async {
    try {
      final list = await _repo.listCalendars();
      if (!mounted) return;
      setState(() { _calendars = list; });
    } catch (_) {}
  }

  Future<void> _reloadRange(DateTime startLocal, DateTime endLocal) async {
    final res = await _repo.expand(startLocal.toUtc(), endLocal.toUtc());
    if (!mounted) return;
    setState(() { _events = res; _loading = false; });
  }

  Future<void> _reloadForCurrentView() async {
    switch (_view) {
      case CalendarView.month:
        await _reloadMonthEvents();
        break;
      case CalendarView.day:
        final s = DateTime(_focusDay.year, _focusDay.month, _focusDay.day);
        await _reloadRange(s, s.add(const Duration(days: 1)));
        break;
      case CalendarView.threeDay:
        final s3 = DateTime(_focusDay.year, _focusDay.month, _focusDay.day);
        await _reloadRange(s3, s3.add(const Duration(days: 3)));
        break;
      case CalendarView.week:
        final ws = _weekStartLocal(_focusDay);
        await _reloadRange(ws, ws.add(const Duration(days: 7)));
        break;
      case CalendarView.agenda:
        final sA = DateTime(_focusDay.year, _focusDay.month, _focusDay.day);
        await _reloadRange(sA, sA.add(const Duration(days: 30)));
        break;
    }
  }

  Future<void> _step(int direction) async {
    setState(() { _loading = true; });
    switch (_view) {
      case CalendarView.month:
        _visibleMonth = _addMonths(_visibleMonth, direction);
        await _reloadMonthEvents();
        break;
      case CalendarView.day:
        _focusDay = _focusDay.add(Duration(days: direction));
        await _reloadForCurrentView();
        break;
      case CalendarView.threeDay:
        _focusDay = _focusDay.add(Duration(days: 3 * direction));
        await _reloadForCurrentView();
        break;
      case CalendarView.week:
        _focusDay = _focusDay.add(Duration(days: 7 * direction));
        await _reloadForCurrentView();
        break;
      case CalendarView.agenda:
        _focusDay = _focusDay.add(Duration(days: 7 * direction));
        await _reloadForCurrentView();
        break;
    }
  }

  void _setView(CalendarView v) {
    setState(() { _view = v; _loading = true; });
    _reloadForCurrentView();
  }

  String _titleForView() {
    switch (_view) {
      case CalendarView.month:
        return _titleForMonth(_visibleMonth);
      case CalendarView.day:
        return _formatDay(_focusDay);
      case CalendarView.threeDay:
        final s = DateTime(_focusDay.year, _focusDay.month, _focusDay.day);
        final e = s.add(const Duration(days: 2));
        return '${_formatShort(s)} — ${_formatDay(e)}';
      case CalendarView.week:
        final ws = _weekStartLocal(_focusDay);
        final we = ws.add(const Duration(days: 6));
        return '${_formatShort(ws)} — ${_formatDay(we)}';
      case CalendarView.agenda:
        return 'Список: ${_formatShort(_focusDay)} → 30д';
    }
  }

  static DateTime _weekStartLocal(DateTime d) {
    final ld = DateTime(d.year, d.month, d.day);
    final delta = (ld.weekday + 6) % 7;
    return ld.subtract(Duration(days: delta));
  }

  String _formatDay(DateTime d) {
    const months = ['Янв','Фев','Мар','Апр','Май','Июн','Июл','Авг','Сен','Окт','Ноя','Дек'];
    const wk = ['Пн','Вт','Ср','Чт','Пт','Сб','Вс'];
    final l = d;
    return '${wk[(l.weekday+6)%7]}, ${l.day} ${months[l.month-1]} ${l.year}';
  }

  String _formatShort(DateTime d) {
    const months = ['Янв','Фев','Мар','Апр','Май','Июн','Июл','Авг','Сен','Окт','Ноя','Дек'];
    final l = d;
    return '${l.day} ${months[l.month-1]}';
  }
}

class _MonthView extends StatelessWidget {
  final DateTime month; // any day within month
  final void Function(DateTime day)? onTapDay;
  final void Function(DateTime day)? onLongPressDay;
  final List<EventEntity> events;
  final List<CalendarEntity> calendars;
  const _MonthView({required this.month, this.onTapDay, this.onLongPressDay, required this.events, required this.calendars});

  @override
  Widget build(BuildContext context) {
    final firstOfMonth = DateTime(month.year, month.month, 1);
    // Week starts Monday. Dart weekday: Mon=1..Sun=7.
    final firstWeekday = firstOfMonth.weekday; // 1..7
    final leading = (firstWeekday + 6) % 7; // 0 for Monday, 6 for Sunday
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final totalCells = (((leading + daysInMonth) + 6) ~/ 7) * 7; // 35 или 42

    final startDate = firstOfMonth.subtract(Duration(days: leading));
    final today = DateTime.now();
    final isSameDay = (DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

    return Column(
      children: [
        _WeekdayHeader(),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              childAspectRatio: 0.9, // make cells a bit taller to avoid overflow
            ),
            itemCount: totalCells,
            itemBuilder: (_, i) {
              final day = startDate.add(Duration(days: i));
              final inMonth = day.month == month.month && day.year == month.year;
              final isToday = isSameDay(day, today);
              final borderColor = isToday ? Colors.amber : Colors.grey[500]!;
              final bg = Colors.grey[700];
              final textStyle = TextStyle(
                color: inMonth ? Colors.white : Colors.white70.withOpacity(0.5),
                fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
              );
              // Отберём инстансы для этой календарной даты и удалим возможные дубляжи
              final raw = events.where((e) {
                final d = DateTime(day.year, day.month, day.day);
                final startDay = DateTime(e.startUtc.toLocal().year, e.startUtc.toLocal().month, e.startUtc.toLocal().day);
                final endDay = DateTime(e.endUtc.toLocal().year, e.endUtc.toLocal().month, e.endUtc.toLocal().day);
                return !d.isBefore(startDay) && !d.isAfter(endDay);
              });
              final seen = <String>{};
              final dayEvents = <EventEntity>[];
              for (final e in raw) {
                final key = '${e.calendarUid}|${e.parentUid ?? e.uid}|${e.recurrenceId ?? e.startUtc.toIso8601String()}';
                if (seen.add(key)) dayEvents.add(e);
              }
              Color pillColor(String calUid){
                final c = calendars.where((x)=>x.uid==calUid).cast<CalendarEntity?>().firstWhere((x)=>x!=null, orElse: ()=>null);
                if(c==null) return Colors.amber.withOpacity(0.25);
                return _hexColor(c.colorHex).withOpacity(0.25);
              }
              return InkWell(
                onTap: onTapDay == null ? null : () => onTapDay!(day),
                onLongPress: onLongPressDay == null ? null : () => onLongPressDay!(day),
                child: Container(
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: borderColor, width: 0.5),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(6.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: Alignment.topRight,
                          child: Text('${day.day}', style: textStyle),
                        ),
                        const SizedBox(height: 2),
                        ...dayEvents.take(3).map((e) => _EventPill(title: e.title, color: pillColor(e.calendarUid))),
                        if (dayEvents.length > 3)
                          Text('+${dayEvents.length - 3}', style: const TextStyle(fontSize: 10, color: Colors.white70)),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _WeekdayHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const labels = ['Пн','Вт','Ср','Чт','Пт','Сб','Вс'];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: List.generate(7, (i) => Expanded(
          child: Center(
            child: Text(labels[i], style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
          ),
        )),
      ),
    );
  }
}

class _DayListView extends StatelessWidget {
  final DateTime day;
  final List<EventEntity> events;
  final VoidCallback onAdd;
  final void Function(EventEntity e)? onEdit;
  const _DayListView({required this.day, required this.events, required this.onAdd, this.onEdit});

  @override
  Widget build(BuildContext context) {
    final s = DateTime(day.year, day.month, day.day);
    final e = s.add(const Duration(days: 1));
    final items = events
        .where((ev) => !ev.endUtc.isBefore(s.toUtc()) && ev.startUtc.isBefore(e.toUtc()))
        .toList()
      ..sort((a, b) => a.startUtc.compareTo(b.startUtc));

    return Column(
      children: [
        Expanded(
          child: items.isEmpty
              ? const Center(child: Text('Нет событий'))
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemBuilder: (_, i) => _eventCard(items[i]),
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemCount: items.length,
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: ElevatedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Добавить событие'),
          ),
        ),
      ],
    );
  }

  Widget _eventCard(EventEntity e) {
    String fmt(DateTime d) => '${d.toLocal().hour.toString().padLeft(2,'0')}:${d.toLocal().minute.toString().padLeft(2,'0')}';
    final time = e.isAllDay ? 'Весь день' : '${fmt(e.startUtc)} – ${fmt(e.endUtc)}';
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[700],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[500]!, width: 0.5),
      ),
      child: ListTile(
        title: Text(e.title),
        subtitle: Text(time),
        leading: const Icon(Icons.event, color: Colors.amber),
        onTap: onEdit == null ? null : () => onEdit!(e),
      ),
    );
  }
}

class _MultiDayColumns extends StatelessWidget {
  final DateTime start; // local date start
  final int days;
  final List<EventEntity> events;
  final void Function(DateTime day) onAdd;
  final void Function(EventEntity e)? onEdit;
  const _MultiDayColumns({required this.start, required this.days, required this.events, required this.onAdd, this.onEdit});

  @override
  Widget build(BuildContext context) {
    final cols = List.generate(days, (i) => DateTime(start.year, start.month, start.day + i));
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: cols.map((d) => SizedBox(
          width: 320,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                color: Colors.grey[800],
                child: Text(_header(d), style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              Expanded(child: _DayListView(day: d, events: events, onAdd: () => onAdd(d), onEdit: onEdit)),
            ],
          ),
        )).toList(),
      ),
    );
  }

  String _header(DateTime d) {
    const months = ['Янв','Фев','Мар','Апр','Май','Июн','Июл','Авг','Сен','Окт','Ноя','Дек'];
    const wk = ['Пн','Вт','Ср','Чт','Пт','Сб','Вс'];
    return '${wk[(d.weekday+6)%7]}, ${d.day} ${months[d.month-1]}';
  }
}

class _AgendaListView extends StatelessWidget {
  final DateTime start;
  final List<EventEntity> events;
  final VoidCallback onAdd;
  final void Function(EventEntity e)? onEdit;
  const _AgendaListView({required this.start, required this.events, required this.onAdd, this.onEdit});

  @override
  Widget build(BuildContext context) {
    final s = DateTime(start.year, start.month, start.day);
    final e = s.add(const Duration(days: 30));
    final items = events
        .where((ev) => !ev.endUtc.isBefore(s.toUtc()) && ev.startUtc.isBefore(e.toUtc()))
        .toList()
      ..sort((a,b)=> a.startUtc.compareTo(b.startUtc));
    Map<String, List<EventEntity>> byDay = {};
    for (final ev in items) {
      final key = DateTime(ev.startUtc.toLocal().year, ev.startUtc.toLocal().month, ev.startUtc.toLocal().day).toIso8601String();
      byDay.putIfAbsent(key, () => []).add(ev);
    }
    final keys = byDay.keys.toList()..sort();
    return ListView.builder(
      itemCount: keys.length + 1,
      itemBuilder: (_, idx) {
        if (idx == keys.length) {
          return Padding(
            padding: const EdgeInsets.all(12.0),
            child: ElevatedButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('Добавить событие')),
          );
        }
        final key = keys[idx];
        final day = DateTime.parse(key);
        final list = byDay[key]!..sort((a,b)=>a.startUtc.compareTo(b.startUtc));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: Colors.grey[800],
              child: Text(_header(day), style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            ...list.map((e) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: _eventTile(e),
                )),
          ],
        );
      },
    );
  }

  String _header(DateTime d) {
    const months = ['Янв','Фев','Мар','Апр','Май','Июн','Июл','Авг','Сен','Окт','Ноя','Дек'];
    const wk = ['Пн','Вт','Ср','Чт','Пт','Сб','Вс'];
    return '${wk[(d.weekday+6)%7]}, ${d.day} ${months[d.month-1]}';
  }

  Widget _eventTile(EventEntity e) {
    String fmt(DateTime d) => '${d.toLocal().hour.toString().padLeft(2,'0')}:${d.toLocal().minute.toString().padLeft(2,'0')}';
    final time = e.isAllDay ? 'Весь день' : '${fmt(e.startUtc)} – ${fmt(e.endUtc)}';
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[700],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[500]!, width: 0.5),
      ),
      child: ListTile(
        title: Text(e.title),
        subtitle: Text(time),
        leading: const Icon(Icons.event, color: Colors.amber),
        onTap: onEdit == null ? null : () => onEdit!(e),
      ),
    );
  }
}

class _ManageCalendarsDialog extends StatefulWidget {
  final ApiCalendarRepository repo;
  const _ManageCalendarsDialog({required this.repo});
  @override
  State<_ManageCalendarsDialog> createState() => _ManageCalendarsDialogState();
}

class _ManageCalendarsDialogState extends State<_ManageCalendarsDialog> {
  List<CalendarEntity> _items = [];
  final _colors = [
    '#FFC107','#FF5722','#E91E63','#9C27B0','#3F51B5','#2196F3','#00BCD4','#009688','#4CAF50','#8BC34A','#CDDC39','#FF9800',
  ];

  @override
  void initState(){ super.initState(); _load(); }
  Future<void> _load() async { final list = await widget.repo.listCalendars(); if(mounted) setState(()=>_items=list); }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Календари'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final c in _items)
              ListTile(
                leading: Container(width:18,height:18,decoration: BoxDecoration(color: _hexColor(c.colorHex), shape: BoxShape.circle)),
                title: Text(c.name),
                trailing: IconButton(
                  icon: const Icon(Icons.edit, color: Colors.amber),
                  onPressed: () async { await _edit(c); await _load(); },
                ),
              ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: ElevatedButton.icon(
                onPressed: () async { await _create(); await _load(); },
                icon: const Icon(Icons.add),
                label: const Text('Создать календарь'),
              ),
            )
          ],
        ),
      ),
      actions: [ TextButton(onPressed: ()=>Navigator.of(context).pop(), child: const Text('Закрыть')) ],
    );
  }

  Future<void> _create() async {
    String name = '';
    String color = _colors.first;
    final ok = await showDialog<bool>(context: context, builder: (_){
      return _CalendarEditDialog(title: 'Новый календарь', name: name, colorHex: color, colors: _colors,
        onChanged: (n,c){ name=n; color=c; });
    });
    if(ok==true && name.trim().isNotEmpty){ await widget.repo.createCalendar(name.trim(), colorHex: color); }
  }
  Future<void> _edit(CalendarEntity c) async {
    String name = c.name; String color = c.colorHex;
    final ok = await showDialog<bool>(context: context, builder: (_){
      return _CalendarEditDialog(title: 'Редактировать календарь', name: name, colorHex: color, colors: _colors,
        onChanged: (n,col){ name=n; color=col; });
    });
    if(ok==true && name.trim().isNotEmpty){ await widget.repo.updateCalendar(c.uid, name: name.trim(), colorHex: color); }
  }
}

class _CalendarEditDialog extends StatefulWidget{
  final String title; final String name; final String colorHex; final List<String> colors; final void Function(String,String) onChanged;
  const _CalendarEditDialog({required this.title, required this.name, required this.colorHex, required this.colors, required this.onChanged});
  @override State<_CalendarEditDialog> createState()=>_CalendarEditDialogState();
}
class _CalendarEditDialogState extends State<_CalendarEditDialog>{
  late TextEditingController _ctrl; late String _color;
  @override void initState(){ super.initState(); _ctrl=TextEditingController(text: widget.name); _color=widget.colorHex; }
  @override Widget build(BuildContext context){
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(controller: _ctrl, decoration: const InputDecoration(labelText: 'Название')), const SizedBox(height: 12),
            const Text('Цвет'), const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for(final h in widget.colors)
                GestureDetector(onTap: ()=> setState(()=>_color=h), child: Container(
                  width: 26, height: 26,
                  decoration: BoxDecoration(color: _hexColor(h), shape: BoxShape.circle, border: Border.all(color: _color==h? Colors.white: Colors.transparent, width: 2)),
                )),
            ]),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: ()=> Navigator.of(context).pop(false), child: const Text('Отмена')),
        ElevatedButton(onPressed: (){ widget.onChanged(_ctrl.text, _color); Navigator.of(context).pop(true); }, child: const Text('Сохранить')),
      ],
    );
  }
}

class _EventPill extends StatelessWidget {
  final String title;
  final Color color;
  const _EventPill({required this.title, this.color = const Color(0x80FFC107)});
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
    );
  }
}

Color _hexColor(String hex){
  var h = hex.replaceAll('#','');
  if(h.length==6) h='FF$h';
  return Color(int.parse(h, radix:16));
}

class _WeekPlaceholder extends StatelessWidget {
  final String title;
  const _WeekPlaceholder({required this.title});
  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

class _DayPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

class _AgendaPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

import 'package:flutter/material.dart';
import '../data/api_repository.dart';
import '../domain/entities.dart';
import 'event_editor.dart';

/// Экран «День»: показывает все события за сутки, позволяет быстро открыть
/// редактор (тап) или создать новое (FAB). После возврата из редактора
/// список перезагружается, чтобы изменения были видны сразу.
class DaySchedulePage extends StatefulWidget {
  final DateTime day;
  final ApiCalendarRepository repo;
  const DaySchedulePage({super.key, required this.day, required this.repo});

  @override
  State<DaySchedulePage> createState() => _DaySchedulePageState();
}

class _DaySchedulePageState extends State<DaySchedulePage> {
  late Future<List<EventEntity>> _future;
  List<CalendarEntity> _calendars = [];

  @override
  void initState() {
    super.initState();
    _future = _load();
    _loadCalendars();
  }

  Future<List<EventEntity>> _load() {
    // Для корректного отображения многодневных событий берём небольшое окно
    // «назад» и далее фильтруем по пересечению суток.
    const lookbackDays = 7;
    final startLocal = DateTime(widget.day.year, widget.day.month, widget.day.day);
    final start = startLocal.subtract(const Duration(days: lookbackDays)).toUtc();
    final end = startLocal.add(const Duration(days: 1)).toUtc();
    return widget.repo.expand(start, end);
  }

  Future<void> _reload() async {
    setState(() { _future = _load(); });
    try { final cals = await widget.repo.listCalendars(); if(mounted) setState(()=> _calendars = cals); } catch(_){ }
  }

  Future<void> _loadCalendars() async {
    try { final cals = await widget.repo.listCalendars(); if(mounted) setState(()=> _calendars = cals); } catch(_){ }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_title(widget.day))),
      body: FutureBuilder<List<EventEntity>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          // Сортируем события по времени начала; развёрнутые повторения уже
          // находятся в диапазоне [день, день+1).
          final all = (snap.data ?? const <EventEntity>[]);
          // Фильтрация по пересечению с текущими сутками (локально)
          final dayStartLocal = DateTime(widget.day.year, widget.day.month, widget.day.day);
          final dayEndLocal = dayStartLocal.add(const Duration(days: 1));
          bool overlaps(EventEntity e){
            final s = e.startUtc.toLocal();
            final en = e.endUtc.toLocal();
            return s.isBefore(dayEndLocal) && en.isAfter(dayStartLocal);
          }
          final items = all.where(overlaps).toList()
            ..sort((a,b)=>a.startUtc.compareTo(b.startUtc));
          if (items.isEmpty) {
            return const Center(child: Text('Нет событий'));
          }
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final e = items[i];
                return Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[700],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[500]!, width: 0.5),
                  ),
                  child: ListTile(
                    title: Text(e.title),
                    subtitle: Text(_timeRange(e)),
                    leading: Container(width: 14, height: 14, decoration: BoxDecoration(color: _calColor(e.calendarUid), shape: BoxShape.circle)),
                    onTap: () async {
                      final saved = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(builder: (_) => EventEditorPage(event: e, repo: widget.repo)),
                      );
                      if (saved == true) _reload();
                    },
                  ),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'day-fab',
        onPressed: () async {
          final saved = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => EventEditorPage(initialDay: widget.day, repo: widget.repo)),
          );
          if (saved == true) _reload();
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  String _title(DateTime d) {
    const months = ['Январь','Февраль','Март','Апрель','Май','Июнь','Июль','Август','Сентябрь','Октябрь','Ноябрь','Декабрь'];
    const wk = ['Пн','Вт','Ср','Чт','Пт','Сб','Вс'];
    final l = d.toLocal();
    return '${wk[(l.weekday+6)%7]}, ${l.day} ${months[l.month-1]} ${l.year}';
  }

  String _timeRange(EventEntity e) {
    String fmt(DateTime d) =>
      '${d.toLocal().hour.toString().padLeft(2,'0')}:${d.toLocal().minute.toString().padLeft(2,'0')}';
    if (e.isAllDay) return 'Весь день';
    return '${fmt(e.startUtc)} – ${fmt(e.endUtc)}';
  }
  Color _calColor(String uid){
    final c = _calendars.where((x)=>x.uid==uid).cast<CalendarEntity?>().firstWhere((x)=>x!=null, orElse: ()=>null);
    if(c==null) return Colors.amber;
    return _hexColor(c.colorHex);
  }
}

// Хелпер: перевод HEX (#RRGGBB или #AARRGGBB) в Color
Color _hexColor(String hex){
  var h = hex.replaceAll('#','');
  if(h.length==6) h='FF$h';
  return Color(int.parse(h, radix:16));
}

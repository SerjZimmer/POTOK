import 'package:flutter/material.dart';
import '../data/file_repository.dart';
import '../domain/entities.dart';
import 'event_editor.dart';

class DaySchedulePage extends StatefulWidget {
  final DateTime day;
  final FileCalendarRepository repo;
  const DaySchedulePage({super.key, required this.day, required this.repo});

  @override
  State<DaySchedulePage> createState() => _DaySchedulePageState();
}

class _DaySchedulePageState extends State<DaySchedulePage> {
  late Future<List<EventEntity>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<EventEntity>> _load() {
    final start = DateTime(widget.day.year, widget.day.month, widget.day.day).toUtc();
    final end = start.add(const Duration(days: 1));
    return widget.repo.eventsInRange(start, end);
  }

  Future<void> _reload() async {
    setState(() { _future = _load(); });
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
          final items = (snap.data ?? const <EventEntity>[])..sort((a,b)=>a.startUtc.compareTo(b.startUtc));
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
                    leading: const Icon(Icons.event, color: Colors.amber),
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
}

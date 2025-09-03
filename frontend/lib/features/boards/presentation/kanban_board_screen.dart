import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../data/api_repository.dart';
import '../data/logger.dart';
import 'board_settings_screen.dart';
import 'issue_detail_screen.dart';
import 'widgets/issue_card_helpers.dart';
import 'widgets/form_helpers.dart';

class KanbanBoardScreen extends StatefulWidget {
  final Map<String,dynamic> board;
  const KanbanBoardScreen({super.key, required this.board});
  @override State<KanbanBoardScreen> createState()=>_KanbanBoardScreenState();
}

class _KanbanBoardScreenState extends State<KanbanBoardScreen>{
  final repo = BoardsApiRepository();
  List<Map<String,dynamic>> _columns=[];
  List<Map<String,dynamic>> _issues=[];
  String _search = '';
  List<Map<String,dynamic>> _priorities=[];
  List<Map<String,dynamic>> _fields=[];
  List<String> _createdByPeople=[];
  List<String> _assignedToPeople=[];
  List<String> _responsiblePeople=[];
  int _dueSoonHours = 24;

  @override
  void initState(){
    super.initState();
    BoardsLogger.info('Открыт экран доски', ctx: {'boardId': widget.board['id'], 'name': widget.board['name']});
    _load();
  }

  Future<void> _load() async {
    final cid=widget.board['id'];
    try {
      final cols=await repo.listColumns(cid);
      final iss=await repo.listIssues(cid, search: _search.isNotEmpty ? _search : null);
      final notif = await repo.getBoardNotifications(cid);
      final prios = await repo.listPriorities(cid);
      final flds = await repo.listFields(cid);
      final createdByPpl = await repo.listPeople(cid, 'SETTER');
      final assignedToPpl = await repo.listPeople(cid, 'ASSIGNEE');
      final responsiblePpl = await repo.listPeople(cid, 'RESPONSIBLE');
      if(mounted) setState(()=>{
        _columns=cols,
        _issues=iss,
        _priorities=prios,
        _fields=flds,
        _createdByPeople = createdByPpl,
        _assignedToPeople = assignedToPpl,
        _responsiblePeople = responsiblePpl,
        _dueSoonHours=(notif['dueSoonHours'] as int? ?? 24),
      });
    } catch (e) {
      BoardsLogger.error('Ошибка загрузки доски', error: e, ctx: {'boardId': cid});
    }
  }

  @override
  Widget build(BuildContext context){
    return Scaffold(
      appBar: AppBar(title: Text(widget.board['name']??'Доска'), actions:[
        IconButton(onPressed: () async { await _addColumn(); await _load(); }, icon: const Icon(Icons.view_column_outlined)),
        IconButton(onPressed: () async { final s = await showSearch<String>(context: context, delegate: _IssueSearchDelegate(initial: _search)); if(s!=null){ setState(()=> _search=s); await _load(); } }, icon: const Icon(Icons.search_outlined)),
        IconButton(onPressed: _archiveDone, icon: const Icon(Icons.archive_outlined), tooltip: 'Архивировать выполненные'),
        IconButton(onPressed: () async { await Navigator.of(context).push(MaterialPageRoute(builder: (_)=> BoardSettingsScreen(boardId: widget.board['id'], repo: repo))); await _load(); }, icon: const Icon(Icons.settings_outlined)),
      ]),
      body: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for(final col in _columns)
          Expanded(child: _ColumnWidget(
            boardId: widget.board['id'],
            column: col,
            issues: _issues.where((e)=> e['columnId']==col['id']).toList(),
            priorities: _priorities,
            dueSoonHours: _dueSoonHours,
            onMove: (issueId, countInTarget) async {
              try {
                await repo.moveIssue(issueId, col['id'], countInTarget + 1);
                await _load();
              } on StateError catch(e){
                if(e.message=='WIP_LIMIT'){
                  if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('WIP‑лимит колонки достигнут'), backgroundColor: Colors.red));
                }
              }
            },
            onOpen: (issueId) async {
              await Navigator.of(context).push(MaterialPageRoute(builder: (_)=> IssueDetailScreen(issueId: issueId, repo: repo)));
              await _load();
            },
          ))
      ]),
      floatingActionButton: FloatingActionButton(onPressed: () async{ await _createIssue(); await _load(); }, child: const Icon(Icons.add_circle_outline)),
    );
  }

  Future<void> _archiveDone() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Архивировать задачи?'),
        content: const Text('Все задачи из колонок "Done" будут перемещены в архив. Вы сможете просмотреть их или удалить окончательно на экране архива.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Архивировать'), style: TextButton.styleFrom(foregroundColor: Colors.red)),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await repo.archiveDoneIssues(widget.board['id']);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Выполненные задачи архивированы')),
        );
        await _load();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка архивации: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _createIssue() async {
    final cols = _columns;
    if (cols.isEmpty) return;

    final summaryCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String? priorityKey = _priorities.isNotEmpty ? _priorities.first['key'] : null;
    DateTime? dueDate;
    String type = 'task';
    final createdByCtrl = TextEditingController();
    final assignedToCtrl = TextEditingController();
    final responsibleCtrl = TextEditingController();
    final tagsCtrl = TextEditingController();
    Map<String, dynamic> customFieldValues = {};

    for (final field in _fields) {
      customFieldValues[field['name']] = null;
    }

    await showDialog(
      context: context,
      builder: (_) {
        return StatefulBuilder(builder: (context, setState) {
          return AlertDialog(
            title: const Text('Новая задача'),
            content: DefaultTabController(
              length: 2,
              child: SizedBox(
                width: 600,
                height: 400,
                child: Column(
                  children: [
                    const TabBar(
                      tabs: [
                        Tab(text: 'Основное'),
                        Tab(text: 'Доп. параметры'),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          // Main Tab
                          SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextField(controller: summaryCtrl, decoration: const InputDecoration(labelText: 'Заголовок'), autofocus: true),
                                const SizedBox(height: 8),
                                DropdownButtonFormField<String>(
                                  value: priorityKey,
                                  items: _priorities.map((p) => DropdownMenuItem(value: p['key'] as String, child: Text(p['label'] as String))).toList(),
                                  onChanged: (v) => setState(() => priorityKey = v),
                                  decoration: const InputDecoration(labelText: 'Приоритет'),
                                ),
                                const SizedBox(height: 8),
                                DropdownButtonFormField<String>(
                                  value: type,
                                  items: const [ DropdownMenuItem(value: 'task', child: Text('Задача')), DropdownMenuItem(value: 'bug', child: Text('Баг')), DropdownMenuItem(value: 'story', child: Text('История')) ],
                                  onChanged: (v) => setState(() => type = v ?? 'task'),
                                  decoration: const InputDecoration(labelText: 'Тип'),
                                ),
                                const SizedBox(height: 8),
                                DateField(label: 'Дедлайн', value: dueDate, onChanged: (v)=> setState(()=> dueDate = (v is String)? DateTime.tryParse(v) : v)),
                                const SizedBox(height: 8),
                                SuggestField(controller: createdByCtrl, label: 'Кем поставлена', suggestions: _createdByPeople),
                                const SizedBox(height: 8),
                                SuggestField(controller: assignedToCtrl, label: 'Кому поставлена', suggestions: _assignedToPeople),
                                const SizedBox(height: 8),
                                SuggestField(controller: responsibleCtrl, label: 'Ответственный', suggestions: _responsiblePeople),
                                const SizedBox(height: 8),
                                TextField(controller: tagsCtrl, decoration: const InputDecoration(labelText: 'Теги (CSV)')),
                                const SizedBox(height: 8),
                                TextField(controller: descCtrl, minLines: 3, maxLines: 5, decoration: const InputDecoration(labelText: 'Описание')),
                              ],
                            ),
                          ),
                          // Custom Fields Tab
                          SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                if (_fields.isEmpty) const Center(child: Text('Дополнительные поля не настроены')),
                                for (final field in _fields)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8.0),
                                    child: FieldEditor(field: field, value: customFieldValues[field['name']], onChanged: (val) => setState(() => customFieldValues[field['name']] = val)),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
              ElevatedButton(
                onPressed: () async {
                  if (summaryCtrl.text.trim().isEmpty) return;
                  try {
                    final issueData = {
                      'summary': summaryCtrl.text.trim(),
                      'description': descCtrl.text.trim(),
                      'columnId': cols.first['id'],
                      'priority': priorityKey,
                      'type': type,
                      if (dueDate != null) 'dueDate': dueDate!.toUtc().toIso8601String(),
                      'createdBy': createdByCtrl.text.trim(),
                      'assignedTo': assignedToCtrl.text.trim(),
                      'responsible': responsibleCtrl.text.trim(),
                      'labels': tagsCtrl.text.trim(),
                      ...customFieldValues,
                    };
                    final res = await repo.createIssue(widget.board['id'], issueData);
                    if (mounted) Navigator.pop(context, res);
                  } catch (e) {
                    BoardsLogger.error('Ошибка при создании задачи', error: e);
                  }
                },
                child: const Text('Создать'),
              ),
            ],
          );
        });
      },
    );
  }
}

class _ColumnWidget extends StatelessWidget{
  final String boardId;
  final Map<String,dynamic> column;
  final List<Map<String,dynamic>> issues;
  final List<Map<String,dynamic>> priorities;
  final int dueSoonHours;
  final Future<void> Function(String, int) onMove;
  final Future<void> Function(String) onOpen;
  const _ColumnWidget({super.key, required this.boardId, required this.column, required this.issues, required this.priorities, required this.dueSoonHours, required this.onMove, required this.onOpen});
  @override Widget build(BuildContext context){
    final isDoneColumn = (column['name'] ?? '') == 'Done';
    return DragTarget<String>(
      onAccept: (id)=> onMove(id, issues.length),
      builder:(ctx,_,__){ return Container(
        margin: const EdgeInsets.all(8), padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: Colors.grey[800], borderRadius: BorderRadius.circular(8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[
          Row(children:[
            Expanded(child: Text(column['name']??'', style: const TextStyle(fontWeight: FontWeight.bold))),
            if(column['wipLimit']!=null) Container(padding: const EdgeInsets.symmetric(horizontal:6,vertical:2), decoration: BoxDecoration(color: Colors.amber.withOpacity(0.2), borderRadius: BorderRadius.circular(4)), child: Text('WIP ${column['wipLimit']}', style: const TextStyle(fontSize: 12)))
          ]),
          const SizedBox(height:8),
          Expanded(
            child: LayoutBuilder(
              builder: (ctx, constraints){
                final cardWidth = constraints.maxWidth.isFinite ? constraints.maxWidth : 280.0;
                return ListView(children:[
                  for(final it in issues)
                    _CardDraggable(
                      data: it['id'],
                      width: cardWidth,
                      child: GestureDetector(onTap: ()=> onOpen(it['id']), child: _IssueCard(issue: it, priorities: priorities, dueSoonHours: dueSoonHours, isDone: isDoneColumn)),
                    ),
                ]);
              },
            ),
          ),
      ]),
      );
    },
    );
  }
}

class _IssueCard extends StatelessWidget{
  final Map<String,dynamic> issue;
  final List<Map<String,dynamic>> priorities;
  final int dueSoonHours;
  final bool isDone;
  const _IssueCard({super.key, required this.issue, required this.priorities, required this.dueSoonHours, this.isDone = false});
  @override Widget build(BuildContext context){
    final prKey = (issue['priority']??'MEDIUM').toString();
    final pr = prioOf(priorities, prKey);
    final dueStr = issue['dueDate']?.toString();
    DateTime? due = (dueStr!=null && dueStr.isNotEmpty) ? DateTime.tryParse(dueStr) : null;
    final now = DateTime.now().toUtc();
    bool overdue = false; bool soon = false;
    if(due!=null){
      final dUtc = due.toUtc();
      overdue = dUtc.isBefore(now);
      soon = !overdue && dUtc.difference(now) <= Duration(hours: dueSoonHours);
    }
    return Card(
      color: Colors.grey[700],
      child: Row(children:[
        Container(width: 4, height: 64, color: pr.color),
        Expanded(child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          title: Row(children:[ 
            Expanded(child: Text(issue['summary']??'', overflow: TextOverflow.ellipsis, style: isDone ? const TextStyle(decoration: TextDecoration.lineThrough, color: Colors.white54) : null)),
            if(soon || overdue) Padding(padding: const EdgeInsets.only(left:6), child: Icon(Icons.warning_amber_outlined, size: 18, color: overdue? Colors.redAccent : Colors.amber)),
          ]),
          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[
            Wrap(spacing:8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children:[
              PriorityChip(pr: pr),
              if(due!=null) Row(mainAxisSize: MainAxisSize.min, children:[ const Icon(Icons.event_outlined, size: 14), const SizedBox(width:4), Text(fmtDate(due)) ]),
              Text((issue['type']??'task').toString(), style: const TextStyle(color: Colors.white70)),
            ]),
          ]),
        )),
      ]),
    );
  }
}

class _IssueSearchDelegate extends SearchDelegate<String>{
  final String initial; _IssueSearchDelegate({required this.initial}){ query = initial; }
  @override List<Widget>? buildActions(BuildContext context) => [ if(query.isNotEmpty) IconButton(icon: const Icon(Icons.clear_outlined), onPressed: ()=> query='') ];
  @override Widget? buildLeading(BuildContext context) => IconButton(icon: const Icon(Icons.arrow_back_outlined), onPressed: ()=> close(context, initial));
  @override Widget buildResults(BuildContext context) => Container();
  @override Widget buildSuggestions(BuildContext context) => Container();
  @override void showResults(BuildContext context){ close(context, query); }
}

class _CardDraggable extends StatelessWidget{
  final String data;
  final Widget child;
  final double width;
  const _CardDraggable({required this.data, required this.child, required this.width});
  bool get _isPointerDrag => kIsWeb || defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.linux || defaultTargetPlatform == TargetPlatform.windows;
  @override
  Widget build(BuildContext context){
    final fb = Material(color: Colors.transparent, child: SizedBox(width: width, child: child));
    if(_isPointerDrag){
      return Draggable<String>(data: data, feedback: fb, child: child, childWhenDragging: Opacity(opacity: 0.6, child: child));
    }
    return LongPressDraggable<String>(data: data, feedback: fb, child: child, childWhenDragging: Opacity(opacity: 0.6, child: child));
  }
}

extension on _KanbanBoardScreenState{
  Future<void> _addColumn() async {
    String name=''; int? wip;
    await showDialog(context: context, builder: (_){
      final wipCtrl = TextEditingController();
      return AlertDialog(title: const Text('Новая колонка'), content: SizedBox(width: 360, child: Column(mainAxisSize: MainAxisSize.min, children:[
        TextField(onChanged: (v)=> name=v, decoration: const InputDecoration(labelText: 'Название')),
        const SizedBox(height:8),
        TextField(controller: wipCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'WIP‑лимит (опционально)')),
      ]),), actions:[
        TextButton(onPressed: ()=> Navigator.pop(context), child: const Text('Отмена')),
        ElevatedButton(onPressed: () async { if(name.trim().isEmpty) return; final v = int.tryParse(wipCtrl.text.trim()); await repo.addColumn(widget.board['id'], name.trim(), wip: v); if(mounted) Navigator.pop(context); }, child: const Text('Создать')),
      ]);
    });
  }
}
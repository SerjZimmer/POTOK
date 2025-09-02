import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../data/api_repository.dart';
import '../data/logger.dart';
import 'board_settings_screen.dart';

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
  List<Map<String,dynamic>> _priorities=[]; // [{key,label,colorHex,position}]
  int _dueSoonHours = 24;
  @override void initState(){ super.initState(); BoardsLogger.info('Открыт экран доски', ctx: {'boardId': widget.board['id'], 'name': widget.board['name']}); _load(); }
  Future<void> _load() async {
    final cid=widget.board['id'];
    try {
      final cols=await repo.listColumns(cid);
      final iss=await repo.listIssues(cid, search: _search.isNotEmpty ? _search : null);
      // settings
      final notif = await repo.getBoardNotifications(cid);
      final prios = await repo.listPriorities(cid);
      if(mounted) setState(()=>{
        _columns=cols,
        _issues=iss,
        _priorities=prios,
        _dueSoonHours=(notif['dueSoonHours'] as int? ?? 24),
      });
      BoardsLogger.info('Данные доски загружены', ctx: {'columns': _columns.length, 'issues': _issues.length, if(_search.isNotEmpty) 'search': _search});
    } catch (e) {
      BoardsLogger.error('Ошибка загрузки доски', error: e, ctx: {'boardId': cid});
    }
  }
  @override Widget build(BuildContext context){
    return Scaffold(
      appBar: AppBar(title: Text(widget.board['name']??'Доска'), actions:[
        IconButton(onPressed: () async { BoardsLogger.info('Открыт диалог добавления колонки'); await _addColumn(); await _load(); }, icon: const Icon(Icons.view_column)),
        IconButton(onPressed: () async { final s = await showSearch<String>(context: context, delegate: _IssueSearchDelegate(initial: _search)); if(s!=null){ BoardsLogger.info('Установлен поиск', ctx: {'query': s}); setState(()=> _search=s); await _load(); } }, icon: const Icon(Icons.search)),
        IconButton(onPressed: () async { await Navigator.of(context).push(MaterialPageRoute(builder: (_)=> BoardSettingsScreen(boardId: widget.board['id'], repo: repo))); await _load(); }, icon: const Icon(Icons.settings)),
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
                BoardsLogger.info('Карточка перемещена пользователем', ctx: {'issueId': issueId, 'toColumn': col['id']});
              } on StateError catch(e){
                if(e.message=='WIP_LIMIT'){
                  if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('WIP‑лимит колонки достигнут'), backgroundColor: Colors.red));
                  BoardsLogger.warn('Перемещение отклонено WIP‑лимитом', ctx: {'issueId': issueId, 'toColumn': col['id']});
                } else { rethrow; }
              }
            },
            onOpen: (issueId) async {
              BoardsLogger.info('Открытие карточки', ctx: {'issueId': issueId});
              await Navigator.of(context).push(MaterialPageRoute(builder: (_)=> _IssueDetailScreen(issueId: issueId, repo: repo)));
              await _load();
            },
          ))
      ]),
      floatingActionButton: FloatingActionButton(onPressed: () async{ await _createIssue(); await _load(); }, child: const Icon(Icons.add)),
    );
  }
  Future<void> _createIssue() async {
    final cols=_columns; if(cols.isEmpty) return; String summary=''; String description=''; String type='task'; String priority='MEDIUM'; String colId=cols.first['id']; DateTime? due; String createdByCreate=''; String assignedToCreate=''; String responsibleCreate='';
    final created = await showDialog<Map<String,dynamic>?>(context: context, builder: (_){ return AlertDialog(title: const Text('Новая задача'), content: StatefulBuilder(builder:(ctx,setS){
      return SizedBox(width:360, child: Column(mainAxisSize: MainAxisSize.min, children:[
        TextField(onChanged:(v)=>summary=v, decoration: const InputDecoration(labelText:'Заголовок')),
        const SizedBox(height:8),
        TextField(onChanged:(v)=>description=v, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText:'Описание (необязательно)')),
        const SizedBox(height:8),
        DropdownButtonFormField<String>(value: type, items: const [
          DropdownMenuItem(value:'epic', child: Text('Epic')),
          DropdownMenuItem(value:'story', child: Text('Story')),
          DropdownMenuItem(value:'task', child: Text('Task')),
          DropdownMenuItem(value:'bug', child: Text('Bug')),
          DropdownMenuItem(value:'subtask', child: Text('Subtask')),
        ], onChanged:(v)=> setS(()=> type=v??'task')),
        const SizedBox(height:8),
        DropdownButtonFormField<String>(value: priority, items: const [
          DropdownMenuItem(value:'LOW', child: Text('Low')),
          DropdownMenuItem(value:'MEDIUM', child: Text('Medium')),
          DropdownMenuItem(value:'HIGH', child: Text('High')),
        ], onChanged:(v)=> setS(()=> priority=v??'MEDIUM'), decoration: const InputDecoration(labelText:'Приоритет')),
        const SizedBox(height:8),
        Row(children:[
          Expanded(child: Text(due==null? 'Дедлайн: —' : 'Дедлайн: ${due!.toLocal()}')),
          TextButton(onPressed: () async { final now = DateTime.now(); final picked = await showDatePicker(context: ctx, initialDate: due?? now, firstDate: DateTime(2000), lastDate: DateTime(2100)); if(picked!=null){ setS(()=> due = DateTime(picked.year, picked.month, picked.day)); } }, child: const Text('Выбрать')),
          if(due!=null) TextButton(onPressed: ()=> setS(()=> due=null), child: const Text('Сбросить'))
        ]),
        const SizedBox(height:8),
        TextField(onChanged:(v)=> createdByCreate=v, decoration: const InputDecoration(labelText:'Кем поставлена (опционально)')),
        const SizedBox(height:8),
        TextField(onChanged:(v)=> assignedToCreate=v, decoration: const InputDecoration(labelText:'Кому поставлена (опционально)')),
        const SizedBox(height:8),
        TextField(onChanged:(v)=> responsibleCreate=v, decoration: const InputDecoration(labelText:'Ответственный (опционально)')),
        const SizedBox(height:8),
        DropdownButtonFormField<String>(value: colId, items: [for(final c in cols) DropdownMenuItem(value:c['id'], child: Text(c['name']))], onChanged:(v)=> setS(()=> colId=v??colId)),
      ])); }), actions:[
        TextButton(onPressed: ()=>Navigator.pop(context, null), child: const Text('Отмена')),
        ElevatedButton(onPressed: () async {
          if(summary.trim().isEmpty) return;
          try {
            final res = await repo.createIssue(widget.board['id'], {
              'summary':summary.trim(),
              'description': description.trim().isEmpty? null : description.trim(),
              'type':type,
              'priority': priority,
              if(due!=null) 'dueDate': due!.toUtc().toIso8601String(),
              'createdBy': createdByCreate.trim().isEmpty? null : createdByCreate.trim(),
              'assignedTo': assignedToCreate.trim().isEmpty? null : assignedToCreate.trim(),
              'responsible': responsibleCreate.trim().isEmpty? null : responsibleCreate.trim(),
              'columnId':colId
            });
            BoardsLogger.info('Пользователь создал задачу', ctx: {'id': res['id'], 'columnId': colId});
            if(mounted) Navigator.pop(context, res);
          } catch (e) { BoardsLogger.error('Ошибка при создании задачи', error: e); }
        }, child: const Text('Создать')),
      ], );
    });
    if(created != null && mounted){
      BoardsLogger.info('Задача создана, остаёмся на доске', ctx: {'id': created['id']});
      await _load();
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Карточка создана')));
    }
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
                      child: GestureDetector(onTap: ()=> onOpen(it['id']), child: _IssueCard(issue: it, priorities: priorities, dueSoonHours: dueSoonHours)),
                    ),
                ]);
              },
            ),
          ),
      ]),
      ); },
    );
  }
}

class _IssueCard extends StatelessWidget{
  final Map<String,dynamic> issue;
  final List<Map<String,dynamic>> priorities;
  final int dueSoonHours;
  const _IssueCard({super.key, required this.issue, required this.priorities, required this.dueSoonHours});
  @override Widget build(BuildContext context){
    final prKey = (issue['priority']??'MEDIUM').toString();
    final pr = _prioOf(priorities, prKey);
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
            Expanded(child: Text(issue['summary']??'', overflow: TextOverflow.ellipsis)),
            if(soon || overdue) Padding(padding: const EdgeInsets.only(left:6), child: Icon(Icons.warning_amber_rounded, size: 18, color: overdue? Colors.redAccent : Colors.amber)),
          ]),
          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[
            Wrap(spacing:8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children:[
              _PriorityChip(pr: pr),
              if(due!=null) Row(mainAxisSize: MainAxisSize.min, children:[ const Icon(Icons.event, size: 14), const SizedBox(width:4), Text(_fmtDate(due)) ]),
              Text((issue['type']??'task').toString(), style: const TextStyle(color: Colors.white70)),
            ]),
          ]),
        )),
      ]),
    );
  }
}

String _fmtDate(DateTime d){
  final local = d.toLocal();
  return '${local.year.toString().padLeft(4,'0')}-${local.month.toString().padLeft(2,'0')}-${local.day.toString().padLeft(2,'0')}';
}

class PriorityDef {
  final String key; final String label; final Color color;
  const PriorityDef(this.key, this.label, this.color);
}

class PriorityPalette {
  static final List<PriorityDef> _defs = [
    const PriorityDef('LOW', 'Низкий', Color(0xFF66BB6A)),
    const PriorityDef('MEDIUM', 'Средний', Color(0xFFFFB300)),
    const PriorityDef('HIGH', 'Высокий', Color(0xFFE53935)),
  ];
  static PriorityDef of(String key){
    return _defs.firstWhere((e)=> e.key==key, orElse: ()=> _defs[1]);
  }
  static List<PriorityDef> list() => List.unmodifiable(_defs);
  static void upsert(PriorityDef def){
    final i = _defs.indexWhere((e)=> e.key==def.key);
    if(i>=0) { _defs[i] = def; } else { _defs.add(def); }
  }
}

PriorityDef _prioOf(List<Map<String,dynamic>> defs, String key){
  for(final m in defs){ if((m['key']??'') == key){ final hex = (m['colorHex']??'#FFB300') as String; return PriorityDef(key, (m['label']??key) as String, _hex(hex)); } }
  // fallback к локальной палитре
  return PriorityPalette.of(key);
}

Color _hex(String hex){
  var s = hex.replaceFirst('#','');
  if(s.length==6) s = 'FF$s';
  final v = int.tryParse(s, radix:16) ?? 0xFFFFB300;
  return Color(v);
}

class _PriorityChip extends StatelessWidget{
  final PriorityDef pr; const _PriorityChip({required this.pr});
  @override Widget build(BuildContext context){
    return Container(
      padding: const EdgeInsets.symmetric(horizontal:8, vertical:2),
      decoration: BoxDecoration(color: pr.color.withOpacity(0.2), borderRadius: BorderRadius.circular(10), border: Border.all(color: pr.color.withOpacity(0.7))),
      child: Row(mainAxisSize: MainAxisSize.min, children:[
        Container(width: 8, height: 8, decoration: BoxDecoration(color: pr.color, shape: BoxShape.circle)),
        const SizedBox(width:6),
        Text(pr.label),
      ]),
    );
  }
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

class _IssueSearchDelegate extends SearchDelegate<String>{
  final String initial; _IssueSearchDelegate({required this.initial}){ query = initial; }
  @override List<Widget>? buildActions(BuildContext context) => [ if(query.isNotEmpty) IconButton(icon: const Icon(Icons.clear), onPressed: ()=> query='') ];
  @override Widget? buildLeading(BuildContext context) => IconButton(icon: const Icon(Icons.arrow_back), onPressed: ()=> close(context, initial));
  @override Widget buildResults(BuildContext context) => Container();
  @override Widget buildSuggestions(BuildContext context) => Container();
  @override void showResults(BuildContext context){ close(context, query); }
}

class _IssueDetailScreen extends StatefulWidget{
  final String issueId; final BoardsApiRepository repo;
  const _IssueDetailScreen({required this.issueId, required this.repo});
  @override State<_IssueDetailScreen> createState()=> _IssueDetailScreenState();
}
class _IssueDetailScreenState extends State<_IssueDetailScreen>{
  Map<String,dynamic>? issue;
  List<Map<String,dynamic>> checklist=[];
  List<Map<String,dynamic>> comments=[];
  List<Map<String,dynamic>> columns=[];
  bool _editing = false;
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String _priority = 'MEDIUM';
  String _type = 'task';
  String? _columnId;
  DateTime? _due;
  final _tagsCtrl = TextEditingController();
  final _createdByCtrl = TextEditingController();
  final _assignedToCtrl = TextEditingController();
  final _responsibleCtrl = TextEditingController();
  List<String> _createdBySuggest = [];
  List<String> _assignedToSuggest = [];
  List<String> _responsibleSuggest = [];
  List<Map<String,dynamic>> _fields = [];
  Map<String,dynamic> _fieldValues = {};
  @override void initState(){ super.initState(); _load(); }
  Future<void> _load() async {
    // Load issue first; if this fails, pop with an error.
    try {
      BoardsLogger.info('Загрузка карточки (детали)', ctx: {'id': widget.issueId});
      final it = await widget.repo.getIssue(widget.issueId);
      if(!mounted) return;
      setState((){
        issue = it;
        _titleCtrl.text = (it['summary'] ?? '')?.toString() ?? '';
        _descCtrl.text = (it['description'] ?? '')?.toString() ?? '';
        _priority = (it['priority'] ?? 'MEDIUM')?.toString() ?? 'MEDIUM';
        _type = (it['type'] ?? 'task')?.toString() ?? 'task';
        final due = it['dueDate']?.toString();
        _due = (due!=null && due.isNotEmpty) ? DateTime.tryParse(due) : null;
        _tagsCtrl.text = (it['labels'] ?? '')?.toString() ?? '';
        _createdByCtrl.text = (it['createdBy'] ?? '')?.toString() ?? '';
        _assignedToCtrl.text = (it['assignedTo'] ?? '')?.toString() ?? '';
        _responsibleCtrl.text = (it['responsible'] ?? '')?.toString() ?? '';
      });
    } catch (e) {
      BoardsLogger.error('Не удалось загрузить карточку', error: e, ctx: {'id': widget.issueId});
      if(!mounted) return; ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка загрузки карточки: $e'))); Navigator.pop(context); return;
    }
    // Load checklist, comments, columns separately. Errors are logged and ignored.
    try {
      final cl = await widget.repo.listChecklist(widget.issueId);
      if(mounted) setState(()=> checklist = cl);
      BoardsLogger.info('Детали: чек-лист загружен', ctx: {'count': checklist.length});
    } catch (e) {
      BoardsLogger.error('Не удалось загрузить чек-лист', error: e, ctx: {'id': widget.issueId});
    }
    try {
      final cm = await widget.repo.listComments(widget.issueId);
      if(mounted) setState(()=> comments = cm);
      BoardsLogger.info('Детали: комментарии загружены', ctx: {'count': comments.length});
    } catch (e) {
      BoardsLogger.error('Не удалось загрузить комментарии', error: e, ctx: {'id': widget.issueId});
    }
    try {
      final boardId = (issue?['boardId']?.toString() ?? '');
      if(boardId.isNotEmpty){
        final cols = await widget.repo.listColumns(boardId);
        if(mounted) setState(()=> columns = cols);
        final colId = (issue?['columnId']?.toString());
        if(mounted) setState(()=> _columnId = (cols.any((c)=> c['id'] == colId)) ? colId : null);
        BoardsLogger.info('Детали: колонки загружены', ctx: {'count': columns.length});
        // custom fields & values
        final fs = await widget.repo.listFields(boardId);
        final fv = await widget.repo.getFieldValues(widget.issueId);
        if(mounted) setState(() { _fields = fs; _fieldValues = fv; });
        // people suggestions
        final cb = await widget.repo.listPeople(boardId, 'SETTER');
        final as = await widget.repo.listPeople(boardId, 'ASSIGNEE');
        final rs = await widget.repo.listPeople(boardId, 'RESPONSIBLE');
        if(mounted) setState((){ _createdBySuggest = cb; _assignedToSuggest = as; _responsibleSuggest = rs; });
      }
    } catch (e) {
      BoardsLogger.error('Не удалось загрузить список колонок', error: e, ctx: {'boardId': issue?['boardId']});
    }
  }
  @override void dispose(){ _titleCtrl.dispose(); _descCtrl.dispose(); _tagsCtrl.dispose(); super.dispose(); }
  String _columnName(String? id){
    if(id==null) return '—';
    final m = columns.firstWhere((c)=> c['id']==id, orElse: ()=> {});
    return (m is Map && m.isNotEmpty) ? (m['name']?.toString() ?? '—') : '—';
  }
  @override Widget build(BuildContext context){
    if(issue==null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(title: const Text('Карточка'), actions:[
        IconButton(onPressed: (){ setState(()=> _editing = !_editing); BoardsLogger.info(_editing? 'Режим редактирования включён' : 'Режим редактирования выключен', ctx: {'id': widget.issueId}); }, icon: Icon(_editing? Icons.check : Icons.edit_outlined)),
        IconButton(onPressed: () async { BoardsLogger.info('Удаление карточки', ctx: {'id': widget.issueId}); await widget.repo.deleteIssue(widget.issueId); if(mounted) Navigator.pop(context); }, icon: const Icon(Icons.delete_outline))
      ]),
      body: SingleChildScrollView(child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if(!_editing)...[
            Text(_titleCtrl.text.isEmpty? 'Без названия' : _titleCtrl.text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height:8),
            Builder(builder: (ctx){
              final pr = PriorityPalette.of(_priority);
              final due = _due;
              String dueLabel = '—';
              Color dueColor = Colors.white70;
              if(due!=null){
                final now = DateTime.now();
                final dLoc = due.toLocal();
                final days = dLoc.difference(now).inDays;
                if(dLoc.isBefore(now)) { dueLabel = 'просрочено на ${now.difference(dLoc).inDays} д'; dueColor = Colors.redAccent; }
                else if(now.year==dLoc.year && now.month==dLoc.month && now.day==dLoc.day) { dueLabel = 'сегодня'; dueColor = Colors.amber; }
                else { dueLabel = 'через ${days.abs()} д'; dueColor = Colors.amber; }
              }
              return Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                _PriorityChip(pr: pr),
                Chip(avatar: const Icon(Icons.category, size:16), label: Text(_type)),
                Chip(avatar: const Icon(Icons.view_column, size:16), label: Text(_columnName(issue?['columnId']?.toString()))),
                if(due!=null) Chip(avatar: const Icon(Icons.event, size:16), label: Text('${_fmtDate(due)} • $dueLabel'), labelStyle: TextStyle(color: dueColor)),
              ]);
            }),
            const SizedBox(height:12),
            if(_createdByCtrl.text.isNotEmpty || _assignedToCtrl.text.isNotEmpty || _responsibleCtrl.text.isNotEmpty)
              Column(crossAxisAlignment: CrossAxisAlignment.start, children:[
                const Text('Участники', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height:6),
                if(_createdByCtrl.text.isNotEmpty) Row(children:[ const Icon(Icons.person_outline, size:16), const SizedBox(width:6), Expanded(child: Text('Поставил: ${_createdByCtrl.text}')) ]),
                if(_assignedToCtrl.text.isNotEmpty) Row(children:[ const Icon(Icons.person_add_alt_1_outlined, size:16), const SizedBox(width:6), Expanded(child: Text('Кому: ${_assignedToCtrl.text}')) ]),
                if(_responsibleCtrl.text.isNotEmpty) Row(children:[ const Icon(Icons.verified_user_outlined, size:16), const SizedBox(width:6), Expanded(child: Text('Ответственный: ${_responsibleCtrl.text}')) ]),
              ]),
            if((_tagsCtrl.text).trim().isNotEmpty) ...[
              const SizedBox(height:12),
              const Text('Теги', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height:6),
              Wrap(spacing:6, runSpacing:6, children: [ for(final t in _tagsCtrl.text.split(',').map((e)=> e.trim()).where((e)=> e.isNotEmpty)) Chip(label: Text(t)) ]),
            ],
            const SizedBox(height:12),
            if(checklist.isNotEmpty) ...[
              Builder(builder: (ctx){ final done = checklist.where((e)=> (e['isDone']??false) as bool).length; final total = checklist.length; final v = total==0? 0.0 : done/total; return Column(crossAxisAlignment: CrossAxisAlignment.start, children:[
                const Text('Чек‑лист', style: TextStyle(fontWeight: FontWeight.bold)), const SizedBox(height:6),
                Row(children:[ Expanded(child: LinearProgressIndicator(value: v, minHeight: 6)), const SizedBox(width:8), Text('$done/$total') ])
              ]); }),
              const SizedBox(height:12),
            ],
            if(comments.isNotEmpty) Row(children:[ const Icon(Icons.chat_bubble_outline, size: 16), const SizedBox(width:6), Text('Комментариев: ${comments.length}') ]),
            if(_fields.isNotEmpty) ...[
              const SizedBox(height:12), const Text('Доп. поля', style: TextStyle(fontWeight: FontWeight.bold)), const SizedBox(height:6),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children:[ for(final f in _fields) Padding(padding: const EdgeInsets.only(bottom:6), child: Row(children:[ Expanded(child: Text('${f['name']}: ${(_fieldValues[f['name']] ?? '—').toString()}')) ])) ]),
            ],
            const SizedBox(height:12),
            Text(_descCtrl.text.isEmpty? 'Описание отсутствует' : _descCtrl.text),
          ] else ...[
            TextField(controller: _titleCtrl, decoration: const InputDecoration(labelText: 'Название')),
            const SizedBox(height:8),
            DropdownButtonFormField<String>(value: _priority, items: const [DropdownMenuItem(value:'LOW', child: Text('Low')), DropdownMenuItem(value:'MEDIUM', child: Text('Medium')), DropdownMenuItem(value:'HIGH', child: Text('High'))], onChanged:(v)=> setState(()=> _priority = v??'MEDIUM'), decoration: const InputDecoration(labelText:'Приоритет')),
            const SizedBox(height:8),
            DropdownButtonFormField<String>(value: _type, items: const [
              DropdownMenuItem(value:'epic', child: Text('Epic')),
              DropdownMenuItem(value:'story', child: Text('Story')),
              DropdownMenuItem(value:'task', child: Text('Task')),
              DropdownMenuItem(value:'bug', child: Text('Bug')),
              DropdownMenuItem(value:'subtask', child: Text('Subtask')),
            ], onChanged:(v)=> setState(()=> _type = v??'task'), decoration: const InputDecoration(labelText:'Тип')),
            const SizedBox(height:8),
          if(columns.isNotEmpty)
              DropdownButtonFormField<String>(value: _columnId, items: [for(final c in columns) DropdownMenuItem(value: c['id'] as String, child: Text(c['name'] as String))], onChanged:(v)=> setState(()=> _columnId = v), decoration: const InputDecoration(labelText:'Колонка')),
            const SizedBox(height:8),
            Row(children:[
              Expanded(child: _SuggestField(controller: _createdByCtrl, label: 'Кем поставлена', suggestions: _createdBySuggest)),
              const SizedBox(width:8),
              ElevatedButton(onPressed: () async { final bid = issue?['boardId']?.toString() ?? ''; if(bid.isEmpty) return; final name = _createdByCtrl.text.trim(); if(name.isEmpty) return; await widget.repo.addPerson(bid, 'SETTER', name); if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Имя сохранено'))); }, child: const Text('Сохранить имя')),
            ]),
            const SizedBox(height:8),
            Row(children:[
              Expanded(child: _SuggestField(controller: _assignedToCtrl, label: 'Кому поставлена', suggestions: _assignedToSuggest)),
              const SizedBox(width:8),
              ElevatedButton(onPressed: () async { final bid = issue?['boardId']?.toString() ?? ''; if(bid.isEmpty) return; final name = _assignedToCtrl.text.trim(); if(name.isEmpty) return; await widget.repo.addPerson(bid, 'ASSIGNEE', name); if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Имя сохранено'))); }, child: const Text('Сохранить имя')),
            ]),
            const SizedBox(height:8),
            Row(children:[
              Expanded(child: _SuggestField(controller: _responsibleCtrl, label: 'Ответственный', suggestions: _responsibleSuggest)),
              const SizedBox(width:8),
              ElevatedButton(onPressed: () async { final bid = issue?['boardId']?.toString() ?? ''; if(bid.isEmpty) return; final name = _responsibleCtrl.text.trim(); if(name.isEmpty) return; await widget.repo.addPerson(bid, 'RESPONSIBLE', name); if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Имя сохранено'))); }, child: const Text('Сохранить имя')),
            ]),
            const SizedBox(height:8),
            const Divider(height:24),
            const Text('Доп. поля', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height:8),
            for(final f in _fields) ...[
              _FieldEditor(field: f, value: _fieldValues[f['name']] , onChanged: (val){ setState(()=> _fieldValues[f['name']] = val); }),
              const SizedBox(height:8),
            ],
            Row(children:[
              Expanded(child: Text(_due==null? 'Дедлайн: —' : 'Дедлайн: ${_due!.toLocal()}')),
              TextButton(onPressed: () async { final now = DateTime.now(); final picked = await showDatePicker(context: context, initialDate: _due?? now, firstDate: DateTime(2000), lastDate: DateTime(2100)); if(picked!=null){ setState(()=> _due = DateTime(picked.year, picked.month, picked.day)); } }, child: const Text('Выбрать')),
              if(_due!=null) TextButton(onPressed: ()=> setState(()=> _due=null), child: const Text('Сбросить'))
            ]),
            const SizedBox(height:8),
            TextField(controller: _descCtrl, minLines: 3, maxLines: 6, decoration: const InputDecoration(labelText: 'Описание')),
            const SizedBox(height:12),
            Row(children:[ const Text('Теги (CSV): '), Expanded(child: TextField(controller: _tagsCtrl)) , TextButton(onPressed: () async { final tags = _tagsCtrl.text.split(',').map((e)=> e.trim()).where((e)=> e.isNotEmpty).toList(); BoardsLogger.info('Обновление тегов пользователем', ctx: {'id': widget.issueId, 'tagsCount': tags.length}); await widget.repo.setTagsBulk(widget.issueId, tags); if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Теги обновлены'))); }, child: const Text('Сохранить теги')) ]),
            const SizedBox(height:12),
            Align(alignment: Alignment.centerRight, child: ElevatedButton.icon(onPressed: () async { BoardsLogger.info('Сохранение карточки пользователем', ctx: {'id': widget.issueId}); await _save(); }, icon: const Icon(Icons.save), label: const Text('Сохранить'))),
          ],
          const Divider(height:24),
          Row(children:[ const Text('Чек-лист', style: TextStyle(fontWeight: FontWeight.bold)), const Spacer(), IconButton(onPressed: () async { final id = await _addChecklistDialog(); if(id!=null) { BoardsLogger.info('Добавлен пункт чек-листа', ctx: {'id': id}); await _load(); } }, icon: const Icon(Icons.add)) ]),
          for(final it in checklist)
            CheckboxListTile(value: (it['isDone']??false) as bool, onChanged: (v) async { BoardsLogger.info('Изменение пункта чек-листа', ctx: {'id': it['id'], 'isDone': v==true}); await widget.repo.patchChecklistItem(it['id'] as String, {'isDone': v==true}); await _load(); }, title: Text(it['text'] as String)),
          const Divider(height:24),
          const Text('Комментарии', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height:8),
          for(final c in comments)
            ListTile(title: Text(c['body'] as String), subtitle: Text(c['createdAt'] as String), onLongPress: () async { BoardsLogger.info('Удаление комментария пользователем', ctx: {'id': '${c['id']}'}); await widget.repo.deleteComment('${c['id']}'); await _load(); }),
          _CommentComposer(onSend: (text) async { BoardsLogger.info('Добавление комментария пользователем', ctx: {'id': widget.issueId}); await widget.repo.addComment(widget.issueId, text); await _load(); }),
          const SizedBox(height:24),
        ]),
      )),
    );
  }
  Future<void> _save() async {
    final patch = <String,dynamic>{
      'summary': _titleCtrl.text.trim(),
      'description': _descCtrl.text,
      'priority': _priority,
      'type': _type,
      'due_date': _due?.toUtc().toIso8601String(),
      'labels': _tagsCtrl.text.trim(),
      'createdBy': _createdByCtrl.text.trim().isEmpty? null : _createdByCtrl.text.trim(),
      'assignedTo': _assignedToCtrl.text.trim().isEmpty? null : _assignedToCtrl.text.trim(),
      'responsible': _responsibleCtrl.text.trim().isEmpty? null : _responsibleCtrl.text.trim(),
    };
    await widget.repo.patchIssue(widget.issueId, patch);
    // сохранить значения доп. полей
    if(_fields.isNotEmpty){
      final payload = <String,dynamic>{};
      for(final f in _fields){ final name = f['name'] as String; payload[name] = _fieldValues[name]; }
      await widget.repo.putFieldValues(widget.issueId, payload);
    }
    // Move if column changed
    if(_columnId != null && issue != null && _columnId != (issue!['columnId']?.toString())){
      // append to end of column
      final bid = (issue!['boardId']?.toString() ?? '');
      final count = bid.isEmpty ? 0 : (await widget.repo.listIssues(bid, columnId: _columnId)).length;
      await widget.repo.moveIssue(widget.issueId, _columnId!, count+1);
    }
    if(mounted) {
      await _load();
      setState(()=> _editing = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Сохранено')));
    }
  }
  Future<String?> _addChecklistDialog() async {
    String text = '';
    await showDialog(context: context, builder: (_){
      return AlertDialog(title: const Text('Добавить пункт'), content: TextField(onChanged:(v)=> text=v, decoration: const InputDecoration(labelText: 'Текст')), actions:[
        TextButton(onPressed: ()=> Navigator.pop(context), child: const Text('Отмена')),
        ElevatedButton(onPressed: (){ Navigator.pop(context); }, child: const Text('Добавить')),
      ]);
    });
    if(text.trim().isEmpty) return null;
    final order = (checklist.isNotEmpty? (checklist.map((e)=> (e['orderIndex']??0) as int).reduce((a,b)=> a>b?a:b)) : 0) + 1;
    final item = await widget.repo.addChecklistItem(widget.issueId, text.trim(), order);
    return item['id'] as String?;
  }
}

class _CommentComposer extends StatefulWidget{
  final Future<void> Function(String) onSend; const _CommentComposer({required this.onSend});
  @override State<_CommentComposer> createState()=> _CommentComposerState();
}
class _CommentComposerState extends State<_CommentComposer>{
  final ctrl = TextEditingController();
  @override void dispose(){ ctrl.dispose(); super.dispose(); }
  @override Widget build(BuildContext context){
    return Row(children:[
      Expanded(child: TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'Комментарий'))),
      IconButton(onPressed: () async { final t = ctrl.text.trim(); if(t.isEmpty) return; ctrl.clear(); await widget.onSend(t); }, icon: const Icon(Icons.send))
    ]);
  }
}

class _SuggestField extends StatelessWidget{
  final TextEditingController controller;
  final String label;
  final List<String> suggestions;
  const _SuggestField({required this.controller, required this.label, required this.suggestions});
  @override
  Widget build(BuildContext context){
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children:[
      TextField(controller: controller, decoration: InputDecoration(labelText: label)),
      if(suggestions.isNotEmpty)
        SizedBox(
          height: 32,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for(final s in suggestions)
              Padding(padding: const EdgeInsets.only(right: 6), child: ActionChip(label: Text(s), onPressed: (){ controller.text = s; })),
          ]),
        ),
    ]);
  }
}

class _FieldEditor extends StatelessWidget{
  final Map<String,dynamic> field; final dynamic value; final ValueChanged<dynamic> onChanged;
  const _FieldEditor({required this.field, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context){
    final type = (field['type']??'text') as String;
    final name = (field['name']??'') as String;
    switch(type){
      case 'number':
        return TextField(controller: TextEditingController(text: value?.toString() ?? ''), keyboardType: TextInputType.number, decoration: InputDecoration(labelText: name), onChanged: (v)=> onChanged(num.tryParse(v)));
      case 'date':
        return _DateField(label: name, value: value, onChanged: onChanged);
      case 'enum':
        final opts = _parseOptions(field['options']);
        return DropdownButtonFormField<String>(value: (value?.toString().isEmpty ?? true) ? null : value.toString(), items: [for(final o in opts) DropdownMenuItem(value:o, child: Text(o))], onChanged: (v)=> onChanged(v), decoration: InputDecoration(labelText: name));
      case 'user':
        return TextField(controller: TextEditingController(text: value?.toString() ?? ''), decoration: InputDecoration(labelText: name), onChanged: (v)=> onChanged(v));
      default:
        return TextField(controller: TextEditingController(text: value?.toString() ?? ''), decoration: InputDecoration(labelText: name), onChanged: (v)=> onChanged(v));
    }
  }
  List<String> _parseOptions(dynamic raw){
    if(raw==null) return const [];
    try { return (raw is String) ? (raw.trim().isEmpty? [] : List<String>.from((jsonDecode(raw) as List).map((e)=> e.toString()))) : List<String>.from((raw as List).map((e)=> e.toString())); } catch(_){ return const []; }
  }
}

class _DateField extends StatefulWidget{
  final String label; final dynamic value; final ValueChanged<dynamic> onChanged;
  const _DateField({required this.label, this.value, required this.onChanged});
  @override State<_DateField> createState()=> _DateFieldState();
}
class _DateFieldState extends State<_DateField>{
  DateTime? _val;
  @override void initState(){ super.initState(); _val = (widget.value is String)? DateTime.tryParse(widget.value): null; }
  @override Widget build(BuildContext context){
    return Row(children:[
      Expanded(child: Text('${widget.label}: ${_val==null? '—' : _val!.toLocal()}')),
      TextButton(onPressed: () async { final now=DateTime.now(); final picked = await showDatePicker(context: context, initialDate: _val?? now, firstDate: DateTime(2000), lastDate: DateTime(2100)); if(picked!=null){ setState(()=> _val = DateTime(picked.year, picked.month, picked.day)); widget.onChanged(_val!.toUtc().toIso8601String()); } }, child: const Text('Выбрать')),
      if(_val!=null) TextButton(onPressed: (){ setState(()=> _val=null); widget.onChanged(null); }, child: const Text('Сбросить'))
    ]);
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
      ])), actions:[
        TextButton(onPressed: ()=> Navigator.pop(context), child: const Text('Отмена')),
        ElevatedButton(onPressed: () async { if(name.trim().isEmpty) return; final v = int.tryParse(wipCtrl.text.trim()); await repo.addColumn(widget.board['id'], name.trim(), wip: v); if(mounted) Navigator.pop(context); }, child: const Text('Создать')),
      ]);
    });
  }
}

import 'dart:convert';
import 'package:flutter/material.dart';
import '../data/api_repository.dart';
import '../data/logger.dart';
import 'widgets/issue_card_helpers.dart';
import 'widgets/form_helpers.dart';

class IssueDetailScreen extends StatefulWidget{
  final String issueId; final BoardsApiRepository repo;
  final bool isArchived;
  const IssueDetailScreen({required this.issueId, required this.repo, this.isArchived = false, super.key});
  @override State<IssueDetailScreen> createState()=> _IssueDetailScreenState();
}
class _IssueDetailScreenState extends State<IssueDetailScreen>{
  Map<String,dynamic>? issue;
  List<Map<String,dynamic>> checklist=[];
  List<Map<String,dynamic>> comments=[];
  List<Map<String,dynamic>> columns=[];
  List<Map<String,dynamic>> _priorities=[];
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
    try {
      final it = widget.isArchived
          ? await widget.repo.getArchivedIssue(widget.issueId)
          : await widget.repo.getIssue(widget.issueId);
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
      if(!mounted) return; ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка загрузки карточки: $e'))); Navigator.pop(context); return;
    }
    try {
      final cl = await widget.repo.listChecklist(widget.issueId);
      if(mounted) setState(()=> checklist = cl);
    } catch (e) { BoardsLogger.error('Не удалось загрузить чек-лист', error: e, ctx: {'id': widget.issueId}); }
    try {
      final cm = await widget.repo.listComments(widget.issueId);
      if(mounted) setState(()=> comments = cm);
    } catch (e) { BoardsLogger.error('Не удалось загрузить комментарии', error: e, ctx: {'id': widget.issueId}); }
    try {
      final boardId = (issue?['boardId']?.toString() ?? '');
      if(boardId.isNotEmpty){
        final cols = await widget.repo.listColumns(boardId);
        if(mounted) setState(()=> columns = cols);
        final colId = (issue?['columnId']?.toString());
        if(mounted) setState(()=> _columnId = (cols.any((c)=> c['id'] == colId)) ? colId : null);
        final fs = await widget.repo.listFields(boardId);
        final fv = await widget.repo.getFieldValues(widget.issueId);
        if(mounted) setState(() { _fields = fs; _fieldValues = fv; });
        final cb = await widget.repo.listPeople(boardId, 'SETTER');
        final as = await widget.repo.listPeople(boardId, 'ASSIGNEE');
        final rs = await widget.repo.listPeople(boardId, 'RESPONSIBLE');
        if(mounted) setState((){ _createdBySuggest = cb; _assignedToSuggest = as; _responsibleSuggest = rs; });
        final prios = await widget.repo.listPriorities(boardId);
        if(mounted) setState(()=> _priorities = prios);
      }
    } catch (e) { BoardsLogger.error('Не удалось загрузить доп. данные', error: e, ctx: {'boardId': issue?['boardId']}); }
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
      appBar: AppBar(title: const Text('Карточка'), actions: widget.isArchived
        ? [ IconButton(icon: const Icon(Icons.delete_forever_outlined), tooltip: 'Удалить навсегда', onPressed: _confirmPermanentDelete) ]
        : [ IconButton(onPressed: (){ setState(()=> _editing = !_editing); }, icon: Icon(_editing? Icons.check : Icons.edit_outlined)), IconButton(onPressed: _confirmDeleteActiveIssue, icon: const Icon(Icons.delete_outline)) ]),
      body: SingleChildScrollView(child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if(!_editing)...[
            Text(_titleCtrl.text.isEmpty? 'Без названия' : _titleCtrl.text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height:8),
            Builder(builder: (ctx){
              final pr = prioOf(_priorities, _priority);
              final due = _due;
              return Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                PriorityChip(pr: pr),
                Chip(avatar: const Icon(Icons.category_outlined, size:16), label: Text(_type)),
                Chip(avatar: const Icon(Icons.view_column_outlined, size:16), label: Text(_columnName(issue?['columnId']?.toString()))),
                if(due!=null) Chip(avatar: const Icon(Icons.event_outlined, size:16), label: Text(fmtDate(due))),
              ]);
            }),
            const SizedBox(height:12),
            if(_createdByCtrl.text.isNotEmpty) Row(children:[ const Icon(Icons.person_outline, size:16), const SizedBox(width:6), Expanded(child: Text('Поставил: ${_createdByCtrl.text}')) ]),
            if(_assignedToCtrl.text.isNotEmpty) Row(children:[ const Icon(Icons.person_add_alt_1_outlined, size:16), const SizedBox(width:6), Expanded(child: Text('Кому: ${_assignedToCtrl.text}')) ]),
            if(_responsibleCtrl.text.isNotEmpty) Row(children:[ const Icon(Icons.verified_user_outlined, size:16), const SizedBox(width:6), Expanded(child: Text('Ответственный: ${_responsibleCtrl.text}')) ]),
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
              Column(crossAxisAlignment: CrossAxisAlignment.start, children:[ for(final f in _fields) Padding(padding: const EdgeInsets.only(bottom:6), child: Row(children:[ Expanded(child: Text('${f['name']}: ${(_fieldValues[f['name'] ?? '—']).toString()}')) ])) ]),
            ],
            const SizedBox(height:12),
            Text(_descCtrl.text.isEmpty? 'Описание отсутствует' : _descCtrl.text),
          ] else ...[
            TextField(controller: _titleCtrl, decoration: const InputDecoration(labelText: 'Название')),
            const SizedBox(height:8),
            DropdownButtonFormField<String>(value: _priority, items: [for(final p in _priorities) DropdownMenuItem(value: p['key'], child: Text(p['label'] as String))], onChanged:(v)=> setState(()=> _priority = v??'MEDIUM'), decoration: const InputDecoration(labelText:'Приоритет')),
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
              Expanded(child: SuggestField(controller: _createdByCtrl, label: 'Кем поставлена', suggestions: _createdBySuggest)),
              const SizedBox(width:8),
              ElevatedButton(onPressed: () async { final bid = issue?['boardId']?.toString() ?? ''; if(bid.isEmpty) return; final name = _createdByCtrl.text.trim(); if(name.isEmpty) return; await widget.repo.addPerson(bid, 'SETTER', name); if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Имя сохранено'))); }, child: const Text('Сохранить имя')),
            ]),
            const SizedBox(height:8),
            Row(children:[
              Expanded(child: SuggestField(controller: _assignedToCtrl, label: 'Кому поставлена', suggestions: _assignedToSuggest)),
              const SizedBox(width:8),
              ElevatedButton(onPressed: () async { final bid = issue?['boardId']?.toString() ?? ''; if(bid.isEmpty) return; final name = _assignedToCtrl.text.trim(); if(name.isEmpty) return; await widget.repo.addPerson(bid, 'ASSIGNEE', name); if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Имя сохранено'))); }, child: const Text('Сохранить имя')),
            ]),
            const SizedBox(height:8),
            Row(children:[
              Expanded(child: SuggestField(controller: _responsibleCtrl, label: 'Ответственный', suggestions: _responsibleSuggest)),
              const SizedBox(width:8),
              ElevatedButton(onPressed: () async { final bid = issue?['boardId']?.toString() ?? ''; if(bid.isEmpty) return; final name = _responsibleCtrl.text.trim(); if(name.isEmpty) return; await widget.repo.addPerson(bid, 'RESPONSIBLE', name); if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Имя сохранено'))); }, child: const Text('Сохранить имя')),
            ]),
            const SizedBox(height:8),
            const Divider(height:24),
            const Text('Доп. поля', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height:8),
            for(final f in _fields) ...[
              FieldEditor(field: f, value: _fieldValues[f['name']] , onChanged: (val){ setState(()=> _fieldValues[f['name']] = val); }),
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
            Row(children:[ const Text('Теги (CSV): '), Expanded(child: TextField(controller: _tagsCtrl)) , TextButton(onPressed: () async { final tags = _tagsCtrl.text.split(',').map((e)=> e.trim()).where((e)=> e.isNotEmpty).toList(); await widget.repo.setTagsBulk(widget.issueId, tags); if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Теги обновлены'))); }, child: const Text('Сохранить теги')) ]),
            const SizedBox(height:12),
            Align(alignment: Alignment.centerRight, child: ElevatedButton.icon(onPressed: () async { await _save(); }, icon: const Icon(Icons.save_outlined), label: const Text('Сохранить'))),
          ],
          const Divider(height:24),
          Row(children:[ const Text('Чек-лист', style: TextStyle(fontWeight: FontWeight.bold)), const Spacer(), IconButton(onPressed: () async { final id = await _addChecklistDialog(); if(id!=null) { await _load(); } }, icon: const Icon(Icons.add_circle_outline)) ]),
          for(final it in checklist)
            CheckboxListTile(value: (it['isDone']??false) as bool, onChanged: (v) async { await widget.repo.patchChecklistItem(it['id'] as String, {'isDone': v==true}); await _load(); }, title: Text(it['text'] as String)),
          const Divider(height:24),
          const Text('Комментарии', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height:8),
          for(final c in comments)
            ListTile(title: Text(c['body'] as String), subtitle: Text(c['createdAt'] as String), onLongPress: () async { await widget.repo.deleteComment('${c['id']}'); await _load(); }),
          CommentComposer(onSend: (text) async { await widget.repo.addComment(widget.issueId, text); await _load(); }),
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
    if(_fields.isNotEmpty){
      final payload = <String,dynamic>{};
      for(final f in _fields){ final name = f['name'] as String; payload[name] = _fieldValues[name]; }
      await widget.repo.putFieldValues(widget.issueId, payload);
    }
    if(_columnId != null && issue != null && _columnId != (issue!['columnId']?.toString())){
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

  Future<void> _confirmPermanentDelete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить задачу?'),
        content: const Text('Задача будет удалена навсегда. Это действие нельзя отменить.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await widget.repo.deleteArchivedIssue(widget.issueId);
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _confirmDeleteActiveIssue() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить задачу?'),
        content: const Text('Задача будет удалена с доски.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await widget.repo.deleteIssue(widget.issueId);
      if (mounted) Navigator.pop(context);
    }
  }
}

class CommentComposer extends StatefulWidget{
  final Future<void> Function(String) onSend; const CommentComposer({required this.onSend, super.key});
  @override State<CommentComposer> createState()=> _CommentComposerState();
}
class _CommentComposerState extends State<CommentComposer>{
  final ctrl = TextEditingController();
  @override void dispose(){ ctrl.dispose(); super.dispose(); }
  @override Widget build(BuildContext context){
    return Row(children:[
      Expanded(child: TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'Комментарий'))),
      IconButton(onPressed: () async { final t = ctrl.text.trim(); if(t.isEmpty) return; ctrl.clear(); await widget.onSend(t); }, icon: const Icon(Icons.send_outlined))
    ]);
  }
}

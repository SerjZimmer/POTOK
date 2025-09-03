import 'package:flutter/material.dart';
import '../data/api_repository.dart';

class BoardSettingsScreen extends StatefulWidget{
  final String boardId; final BoardsApiRepository repo;
  const BoardSettingsScreen({super.key, required this.boardId, required this.repo});
  @override State<BoardSettingsScreen> createState()=> _BoardSettingsScreenState();
}

class _BoardSettingsScreenState extends State<BoardSettingsScreen>{
  Map<String,dynamic> _notif = {'dueSoonHours':24,'createCalendarEvent':1,'createDefaultReminders':0,'reminderOffsetsCsv':null};
  List<Map<String,dynamic>> _priorities = [];
  List<Map<String,dynamic>> _fields = [];
  bool _loading = true;
  @override void initState(){ super.initState(); _load(); }
  Future<void> _load() async {
    final n = await widget.repo.getBoardNotifications(widget.boardId);
    final p = await widget.repo.listPriorities(widget.boardId);
    final f = await widget.repo.listFields(widget.boardId);
    if(!mounted) return;
    setState(()=> {_notif=n, _priorities=p, _fields=f, _loading=false});
  }
  @override Widget build(BuildContext context){
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки доски')),
      body: _loading? const Center(child: CircularProgressIndicator()) : SingleChildScrollView(child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[
          const Text('Уведомления', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height:8),
          Row(children:[
            const Text('Скоро дедлайн (часы): '),
            const SizedBox(width:8),
            SizedBox(width: 80, child: TextField(controller: TextEditingController(text: (_notif['dueSoonHours']??24).toString()), keyboardType: TextInputType.number, onChanged: (v){ final i=int.tryParse(v)??24; _notif['dueSoonHours']=i; },)),
          ]),
          SwitchListTile(value: (_notif['createCalendarEvent']??1)==1, onChanged: (v){ setState(()=> _notif['createCalendarEvent']= v?1:0); }, title: const Text('Создавать событие календаря')),
          SwitchListTile(value: (_notif['createDefaultReminders']??0)==1, onChanged: (v){ setState(()=> _notif['createDefaultReminders']= v?1:0); }, title: const Text('Создавать напоминания по умолчанию')),
          TextField(decoration: const InputDecoration(labelText: 'Напоминания (минуты, через запятую)'), controller: TextEditingController(text: (_notif['reminderOffsetsCsv']??'')?.toString() ?? ''), onChanged: (v){ _notif['reminderOffsetsCsv']= v.trim().isEmpty? null : v.trim(); }),
          Align(alignment: Alignment.centerRight, child: ElevatedButton.icon(onPressed: () async { await widget.repo.putBoardNotifications(widget.boardId, _notif); if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Уведомления сохранены'))); }, icon: const Icon(Icons.save_outlined), label: const Text('Сохранить уведомления'))),
          const Divider(height:24),
          Row(children:[ const Text('Приоритеты', style: TextStyle(fontWeight: FontWeight.bold)), const Spacer(), IconButton(onPressed: _addPriority, icon: const Icon(Icons.add_circle_outline)) ]),
          for(final p in _priorities)
            ListTile(title: Text('${p['label']} (${p['key']})'), subtitle: Text('${p['colorHex']}  • позиция ${p['position']}'), trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () async { await widget.repo.deletePriority(widget.boardId, p['key'] as String); await _load(); })),
          const Divider(height:24),
          Row(children:[ const Text('Поля', style: TextStyle(fontWeight: FontWeight.bold)), const Spacer(), IconButton(onPressed: _addField, icon: const Icon(Icons.add_circle_outline)) ]),
          for(final f in _fields)
            ListTile(title: Text('${f['name']}'), subtitle: Text('тип: ${f['type']}${f['options']!=null? ' • options: ${f['options']}' : ''}')),
        ]),
      )),
    );
  }
  Future<void> _addPriority() async {
    String key=''; String label=''; String color='#FFB300'; int position = (_priorities.isEmpty?1: ((_priorities.map((e)=> (e['position']??0) as int).reduce((a,b)=> a>b?a:b))+1));
    await showDialog(context: context, builder: (_){
      return AlertDialog(title: const Text('Новый приоритет'), content: SizedBox(width: 360, child: Column(mainAxisSize: MainAxisSize.min, children:[
        TextField(onChanged:(v)=> key=v, decoration: const InputDecoration(labelText: 'Ключ (например CRITICAL)')),
        TextField(onChanged:(v)=> label=v, decoration: const InputDecoration(labelText: 'Метка (отображаемое имя)')),
        TextField(onChanged:(v)=> color=v, decoration: const InputDecoration(labelText: 'Цвет #RRGGBB или #AARRGGBB')),
        TextField(onChanged:(v)=> position=int.tryParse(v)??position, decoration: InputDecoration(labelText: 'Позиция', hintText: position.toString())),
      ])), actions:[
        TextButton(onPressed: ()=> Navigator.pop(context), child: const Text('Отмена')),
        ElevatedButton(onPressed: () async { if(key.trim().isEmpty||label.trim().isEmpty) return; await widget.repo.upsertPriority(widget.boardId, key.trim(), label.trim(), color.trim(), position); if(mounted) Navigator.pop(context); }, child: const Text('Сохранить'))
      ]);
    });
    await _load();
  }
  Future<void> _addField() async {
    String name=''; String type='text'; String options='';
    await showDialog(context: context, builder: (_){
      return AlertDialog(title: const Text('Новое поле'), content: SizedBox(width: 360, child: Column(mainAxisSize: MainAxisSize.min, children:[
        TextField(onChanged:(v)=> name=v, decoration: const InputDecoration(labelText: 'Название')),
        DropdownButtonFormField<String>(value: type, items: const [
          DropdownMenuItem(value:'text', child: Text('Текст')),
          DropdownMenuItem(value:'number', child: Text('Число')),
          DropdownMenuItem(value:'date', child: Text('Дата')),
          DropdownMenuItem(value:'enum', child: Text('Справочник (enum)')),
          DropdownMenuItem(value:'user', child: Text('Пользователь')),
        ], onChanged:(v)=> type=v??'text'),
        TextField(onChanged:(v)=> options=v, decoration: const InputDecoration(labelText: 'Опции (JSON, опционально)')),
      ])), actions:[
        TextButton(onPressed: ()=> Navigator.pop(context), child: const Text('Отмена')),
        ElevatedButton(onPressed: () async { if(name.trim().isEmpty) return; final res = await widget.repo.addField(widget.boardId, name.trim(), type, options: options.trim().isEmpty? null: options.trim()); if(mounted) Navigator.pop(context, res); }, child: const Text('Создать'))
      ]);
    });
    await _load();
  }
}


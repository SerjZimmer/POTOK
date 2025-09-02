import 'package:flutter/material.dart';
import '../data/api_repository.dart';
import '../data/logger.dart';
import 'kanban_board_screen.dart';
class BoardsListScreen extends StatefulWidget {
  const BoardsListScreen({super.key});
  @override State<BoardsListScreen> createState()=>_BoardsListScreenState();
}
class _BoardsListScreenState extends State<BoardsListScreen>{
  final repo = BoardsApiRepository();
  List<Map<String,dynamic>> _boards = [];
  @override void initState(){ super.initState(); BoardsLogger.info('Открыт экран списка досок'); _load(); }
  Future<void> _load() async {
    try { final list = await repo.listBoards(); if(mounted) setState(()=>_boards=list); BoardsLogger.info('Список досок обновлён', ctx: {'count': _boards.length}); }
    catch(e){ BoardsLogger.error('Не удалось загрузить список досок', error: e); }
  }
  @override Widget build(BuildContext context){
    return Scaffold(
      appBar: AppBar(title: const Text('Доски')),
      body: ListView.builder(
        itemCount: _boards.length,
        itemBuilder: (_,i){ final b=_boards[i]; return ListTile(
          leading: Icon(b['type']=='scrum'? Icons.view_agenda : Icons.view_kanban, color: Colors.amber),
          title: Text(b['name']??'—'),
          subtitle: Text(b['type']??'kanban'),
          onTap: (){ BoardsLogger.info('Открытие доски', ctx: {'id': b['id'], 'name': b['name']}); Navigator.of(context).push(MaterialPageRoute(builder: (_)=> KanbanBoardScreen(board: b))); },
        ); },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async { BoardsLogger.info('Открытие диалога создания доски'); await _createBoard(); await _load(); }, child: const Icon(Icons.add),
      ),
    );
  }
  Future<void> _createBoard() async {
    String name=''; String type='kanban';
    await showDialog(context: context, builder: (_){
      return AlertDialog(title: const Text('Новая доска'), content: StatefulBuilder(builder: (ctx,setS){
        return SizedBox(width: 360, child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(onChanged: (v)=> name=v, decoration: const InputDecoration(labelText: 'Название')),
          const SizedBox(height:12),
          DropdownButtonFormField<String>(value: type, items: const [
            DropdownMenuItem(value:'kanban', child: Text('Kanban')),
            DropdownMenuItem(value:'scrum', child: Text('Scrum')),
          ], onChanged: (v)=> setS(()=> type=v??'kanban')),
        ]));
      }), actions: [
        TextButton(onPressed: ()=> Navigator.pop(context), child: const Text('Отмена')),
        ElevatedButton(onPressed: () async {
          if(name.trim().isEmpty) return;
          try { final res = await repo.createBoard(name.trim(), type); BoardsLogger.info('Создана доска', ctx: {'id': res['id'], 'name': name.trim(), 'type': type}); }
          catch(e){ BoardsLogger.error('Ошибка при создании доски', error: e, ctx: {'name': name.trim(), 'type': type}); }
          if(mounted) Navigator.pop(context);
        }, child: const Text('Создать')),
      ],);
    });
  }
}

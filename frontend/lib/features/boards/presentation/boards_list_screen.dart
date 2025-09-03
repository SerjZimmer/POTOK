import 'package:flutter/material.dart';
import '../data/api_repository.dart';
import '../data/logger.dart';
import 'kanban_board_screen.dart';
import 'archive_screen.dart';
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
      appBar: AppBar(title: const Text('Доски'), actions: [
        IconButton(icon: const Icon(Icons.archive_outlined), onPressed: (){
          Navigator.of(context).push(MaterialPageRoute(builder: (_)=> const ArchivedIssuesScreen()));
        }, tooltip: 'Архив'),
      ]),
      body: ListView.builder(
        itemCount: _boards.length,
        itemBuilder: (_,i){ final b=_boards[i]; return ListTile(
          leading: Icon(b['type']=='scrum'? Icons.view_agenda_outlined : Icons.view_kanban_outlined, color: Colors.amber),
          title: Text(b['name']??'—'),
          subtitle: Text(b['type']??'kanban'),
          onTap: (){ BoardsLogger.info('Открытие доски', ctx: {'id': b['id'], 'name': b['name']}); Navigator.of(context).push(MaterialPageRoute(builder: (_)=> KanbanBoardScreen(board: b))).then((_)=>_load()); },
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            tooltip: 'Удалить доску',
            onPressed: () => _confirmDelete(b['id'], b['name']??'--'),
          ),
        ); },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async { BoardsLogger.info('Открытие диалога создания доски'); await _createBoard(); await _load(); }, child: const Icon(Icons.add_circle_outline),
      ),
    );
  }

  Future<void> _confirmDelete(String id, String name) async {
    bool archiveDone = false;
    final result = await showDialog<Map<String, bool>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Удалить доску?'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Вы уверены, что хотите удалить доску "$name"?\n\nВсе ее колонки и неархивированные задачи будут также удалены. Это действие нельзя отменить.'),
                  const SizedBox(height: 16),
                  CheckboxListTile(
                    title: const Text('Архивировать выполненные задачи'),
                    value: archiveDone,
                    onChanged: (bool? value) {
                      setState(() {
                        archiveDone = value ?? false;
                      });
                    },
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, {'confirmed': false}), child: const Text('Отмена')),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, {'confirmed': true, 'archive': archiveDone}),
                  child: const Text('Удалить'),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null || result['confirmed'] != true) return;

    try {
      if (result['archive'] == true) {
        await repo.archiveDoneIssues(id);
        BoardsLogger.info('Выполненные задачи доски архивированы', ctx: {'id': id});
      }
      await repo.deleteBoard(id);
      BoardsLogger.info('Доска удалена', ctx: {'id': id});
      await _load();
    } catch (e) {
      BoardsLogger.error('Не удалось удалить доску', error: e, ctx: {'id': id});
      if (mounted) {
        ScaffoldMessenger.of(this.context).showSnackBar(SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red));
      }
    }
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

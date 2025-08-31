import 'package:flutter/material.dart';
import 'package:frontend/notes_master_detail_screen.dart';
import 'package:frontend/features/calendar/presentation/calendar_screen.dart';
import 'package:frontend/src/services/note_service.dart';
import 'package:frontend/src/services/folder_service.dart';
import 'package:frontend/features/calendar/data/api_repository.dart';

/// AppShell — корневая «раковина» приложения с нижней навигацией.
/// Переключает между «Заметки» и «Календарь», хранит состояние экранов
/// через IndexedStack, чтобы не пересоздавать виджеты при переключении.
class AppShell extends StatefulWidget {
  final NoteService? noteService;
  final FolderService? folderService;

  const AppShell({super.key, this.noteService, this.folderService});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      NotesMasterDetailScreen(noteService: widget.noteService, folderService: widget.folderService,),
      CalendarScreen(repo: ApiCalendarRepository()),
    ];

    return Scaffold(
      // IndexedStack рисует только активную страницу, остальные остаются в дереве
      // (важно для производительности и сохранения состояния).
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        backgroundColor: Colors.grey[800],
        indicatorColor: Colors.amber.withOpacity(0.2),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.note_outlined),
            selectedIcon: Icon(Icons.note),
            label: 'Заметки',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Календарь',
          ),
        ],
      ),
    );
  }
}

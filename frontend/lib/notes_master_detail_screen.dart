import 'package:flutter/material.dart';
import 'package:frontend/src/models/note.dart';
import 'package:frontend/src/services/note_service.dart';
import 'package:frontend/src/models/folder.dart';
import 'package:frontend/src/services/folder_service.dart';
import 'package:frontend/note_editor.dart';

class NotesMasterDetailScreen extends StatefulWidget {
  const NotesMasterDetailScreen({super.key});

  @override
  State<NotesMasterDetailScreen> createState() => _NotesMasterDetailScreenState();
}

class _NotesMasterDetailScreenState extends State<NotesMasterDetailScreen> {
  List<Note> _notes = [];
  final NoteService _noteService = NoteService();

  List<Folder> _folders = [];
  final FolderService _folderService = FolderService();
  String? _selectedFolderId; // Null means all notes

  @override
  void initState() {
    super.initState();
    _loadNotes();
    _loadFolders();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadNotes([String? folderId]) async {
    print('[NotesMasterDetailScreen] _loadNotes Called with folderId: $folderId');
    try {
      final fetchedNotes = await _noteService.getNotes(folderId);
      print('[NotesMasterDetailScreen] _loadNotes Fetched ${fetchedNotes.length} notes');
      setState(() {
        _notes = fetchedNotes;
        print('[NotesMasterDetailScreen] _notes updated. Current count: ${_notes.length}');
      });
    } catch (e) {
      print('[NotesMasterDetailScreen] Перехвачена ошибка: $e');
    }
  }

  Future<void> _loadFolders() async {
    try {
      final fetchedFolders = await _folderService.getFolders();
      setState(() {
        _folders = fetchedFolders;
      });
    } catch (e) {
      print('[NotesMasterDetailScreen] Перехвачена ошибка при загрузке папок: $e');
    }
  }

  Future<void> _addNote() async {
    final result = await Navigator.of(context).push<Note>(
      MaterialPageRoute(
        builder: (context) => NoteEditorScreen(initialFolderId: _selectedFolderId),
      ),
    );

    if (result != null) {
      try {
        await _noteService.createNote(result);
        _loadNotes(_selectedFolderId);
      } catch (e) {
        print('[NotesMasterDetailScreen] Перехвачена ошибка: $e');
      }
    }
  }

  Future<void> _deleteNote(String id) async {
    try {
      await _noteService.deleteNote(id);
      _loadNotes(_selectedFolderId);
    } catch (e) {
      print('[NotesMasterDetailScreen] Перехвачена ошибка: $e');
    }
  }

  Future<void> _updateNote(Note note) async {
    final result = await Navigator.of(context).push<Note>(
      MaterialPageRoute(
        builder: (context) => NoteEditorScreen(note: note),
      ),
    );

    if (result != null) {
      try {
        await _noteService.updateNote(result);
        _loadNotes(_selectedFolderId);
      } catch (e) {
        print('[NotesMasterDetailScreen] Перехвачена ошибка: $e');
      }
    }
  }

  Future<void> _showCreateFolderDialog() async {
    String? folderName = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        String newFolderName = '';
        return AlertDialog(
          title: const Text('Создать новую папку'),
          content: TextField(
            onChanged: (value) {
              newFolderName = value;
            },
            decoration: const InputDecoration(hintText: 'Название папки'),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Отмена'),
              onPressed: () {
                Navigator.pop(context); // Dismiss dialog
              },
            ),
            TextButton(
              child: const Text('Создать'),
              onPressed: () {
                Navigator.pop(context, newFolderName); // Pass folder name back
              },
            ),
          ],
        );
      },
    );

    if (folderName != null && folderName.isNotEmpty) {
      try {
        await _folderService.createFolder(folderName);
        _loadFolders(); // Refresh folder list
      } catch (e) {
        print('[NotesMasterDetailScreen] Ошибка при создании папки: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedFolderId == null ? 'Все заметки' : _folders.firstWhere((folder) => folder.id == _selectedFolderId).name),
      ),
      body: Row(
        children: <Widget>[
          // Left Panel: Folders
          SizedBox(
            width: 300, // Fixed width for the folder list
            child: ListView(
              children: <Widget>[
                ListTile(
                  leading: const Icon(Icons.folder_open, color: Colors.blueAccent),
                  title: const Text('Все заметки', style: TextStyle(fontSize: 16)),
                  onTap: () {
                    setState(() {
                      _selectedFolderId = null;
                    });
                    _loadNotes();
                  },
                ),
                const Divider(),
                ..._folders.map((folder) => ListTile(
                  leading: const Icon(Icons.folder, color: Colors.blueAccent),
                  title: Text(folder.name, style: const TextStyle(fontSize: 16)),
                  onTap: () {
                    setState(() {
                      _selectedFolderId = folder.id;
                    });
                    _loadNotes(folder.id);
                  },
                )).toList(),
                ListTile(
                  leading: const Icon(Icons.add_box, color: Colors.blueAccent),
                  title: const Text('Создать новую папку', style: TextStyle(fontSize: 16)),
                  onTap: () {
                    _showCreateFolderDialog();
                  },
                ),
              ],
            ),
          ),
          // Right Panel: Notes
          Expanded(
            child: Scaffold(
              floatingActionButton: FloatingActionButton(
                onPressed: _addNote,
                tooltip: 'Новая заметка',
                backgroundColor: Colors.blueAccent, // iOS-like blue
                foregroundColor: Colors.white,
                shape: const CircleBorder(),
                child: const Icon(Icons.add),
              ),
              body: ListView.builder(
                itemCount: _notes.length,
                itemBuilder: (context, index) {
                  final note = _notes[index];
                  return Dismissible(
                    key: Key(note.id),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      color: Colors.red,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.symmetric(horizontal: 20.0),
                      child: const Icon(Icons.delete, color: Colors.white),
                    ),
                    onDismissed: (direction) {
                      _deleteNote(note.id);
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text("${note.title} удалена")));
                    },
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      title: Text(note.title, style: const TextStyle(fontWeight: FontWeight.w500)),
                      subtitle: Text(note.content, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.grey)),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16.0, color: Colors.grey),
                      onTap: () {
                        _updateNote(note);
                      },
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
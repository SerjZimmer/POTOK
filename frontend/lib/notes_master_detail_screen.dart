import 'package:flutter/material.dart';
import 'package:frontend/src/models/note.dart';
import 'package:frontend/src/services/note_service.dart';
import 'package:frontend/src/models/folder.dart';
import 'package:frontend/src/services/folder_service.dart';
import 'package:frontend/note_editor.dart';
import 'package:collection/collection.dart'; // Import for firstWhereOrNull

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
      // Simply refresh the notes list based on the current selection
      _loadNotes(_selectedFolderId);

      // The logic to return to "All Notes" if folder is empty is already in _loadNotes
      // and the AppBar title handles the display.
    } catch (e) {
      print('[NotesMasterDetailScreen] Перехвачена ошибка: $e');
    }
  }

  Future<void> _updateNote(Note note) async {
    final result = await Navigator.of(context).push<Note>(
      MaterialPageRoute(
        builder: (context) => NoteEditorScreen(
          note: note,
          onDelete: () async {
            await _deleteNote(note.id);
            Navigator.of(context).pop(); // Pop the editor screen after deletion
          },
        ),
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
        title: Text(_selectedFolderId == null
            ? 'Все заметки'
            : _folders.any((folder) => folder.id == _selectedFolderId)
                ? _folders.firstWhere((folder) => folder.id == _selectedFolderId).name
                : 'Все заметки'),
      ),
      body: Row(
        children: <Widget>[
          // Left Panel: Folders
          Container(
            width: 300, // Fixed width for the folder list
            decoration: BoxDecoration(
              color: Colors.grey[50], // Light grey background
              border: Border(right: BorderSide(color: Colors.grey[300]!, width: 0.5)), // Subtle right border
            ),
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
                  trailing: IconButton( // Added delete icon
                    icon: const Icon(Icons.delete, color: Colors.redAccent),
                    onPressed: () {
                      // Show confirmation dialog before deleting
                      showDialog(
                        context: context,
                        builder: (BuildContext context) {
                          return AlertDialog(
                            title: const Text('Удалить папку?'),
                            content: Text('Вы уверены, что хотите удалить папку "${folder.name}" и все заметки в ней?'),
                            actions: <Widget>[
                              TextButton(
                                child: const Text('Отмена'),
                                onPressed: () {
                                  Navigator.of(context).pop(); // Dismiss dialog
                                },
                              ),
                              TextButton(
                                child: const Text('Удалить', style: TextStyle(color: Colors.red)),
                                onPressed: () async {
                                  Navigator.of(context).pop(); // Dismiss dialog
                                  try {
                                    await _folderService.deleteFolder(folder.id);
                                    if (_selectedFolderId == folder.id) { // If the deleted folder was selected
                                      setState(() {
                                        _selectedFolderId = null; // Reset selection
                                      });
                                    }
                                    _loadFolders(); // Refresh folder list
                                    _loadNotes(); // Refresh notes list (in case current folder was deleted)
                                  } catch (e) {
                                    print('[NotesMasterDetailScreen] Ошибка при удалении папки: $e');
                                  }
                                },
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                  onTap: () {
                    setState(() {
                      _selectedFolderId = folder.id;
                    });
                    _loadNotes(folder.id);
                  },
                )).toList(),
                ListTile(
                  leading: const Icon(Icons.create_new_folder, color: Colors.blueAccent),
                  title: const Text('Создать новую папку', style: TextStyle(fontSize: 16)),
                  onTap: () {
                    _showCreateFolderDialog();
                  },
                ),
              ],
            ),
          ),
          // Vertical Divider
          const VerticalDivider(width: 1, thickness: 1, color: Colors.grey), // Added divider
          // Right Panel: Notes
          Expanded(
            child: Container( // Wrap in Container for background/shadow
              color: Colors.white, // White background for notes list
              child: Scaffold(
                key: ValueKey(_selectedFolderId ?? 'all_notes'), // Add a key to the Scaffold
                floatingActionButton: FloatingActionButton(
                  onPressed: _addNote,
                  tooltip: 'Новая заметка',
                  backgroundColor: Colors.blueAccent, // iOS-like blue
                  foregroundColor: Colors.white,
                  shape: const CircleBorder(),
                  child: const Icon(Icons.note_add), // Changed icon to note_add
                ),
                body: _notes.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              'Здесь пока нет заметок.',
                              style: TextStyle(fontSize: 18, color: Colors.grey),
                            ),
                            if (_selectedFolderId == null) // Only show "Create Folder" if "All Notes" is selected
                              const SizedBox(height: 10),
                            if (_selectedFolderId == null) // Only show "Create Folder" if "All Notes" is selected
                              ElevatedButton.icon(
                                onPressed: _showCreateFolderDialog,
                                icon: const Icon(Icons.create_new_folder),
                                label: const Text('Создать папку'),
                              ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        key: ValueKey(_notes.length.toString() + (_selectedFolderId ?? '')), // Keep this key
                        itemCount: _notes.length,
                        itemBuilder: (context, index) {
                          final note = _notes[index];
                          return Dismissible(
                            key: ValueKey(note.id),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              color: Colors.red,
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.symmetric(horizontal: 20.0),
                              child: const Icon(Icons.delete, color: Colors.white),
                            ),
                            onDismissed: (direction) async {
                              final deletedNoteId = note.id;
                              setState(() {
                                _notes.removeWhere((n) => n.id == deletedNoteId); // Remove from local list immediately
                              });
                              try {
                                await _noteService.deleteNote(deletedNoteId); // Delete from backend
                              } catch (e) {
                                print('[NotesMasterDetailScreen] Ошибка при удалении заметки: $e');
                              }
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
          ),
        ],
      ),
    );
  }
}

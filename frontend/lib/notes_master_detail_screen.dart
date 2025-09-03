import 'package:flutter/material.dart';
import 'package:frontend/src/models/note.dart';
import 'package:frontend/src/services/note_service.dart';
import 'package:frontend/src/models/folder.dart';
import 'package:frontend/src/services/folder_service.dart';
import 'package:frontend/note_editor.dart';
import 'package:collection/collection.dart'; // Import for firstWhereOrNull
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

/// Экран «Заметки»:
/// - слева список папок (с счетчиками);
/// - справа список заметок, свайп влево удаляет;
/// - FAB создает новую заметку.
///
/// Потоки данных:
/// - _loadFolders() получает папки и затем вызывает _loadNotes() для текущего
///   выбора;
/// - _loadNotes([folderId]) сначала обновляет _allNotes (для счетчиков), затем
///   подгружает видимые заметки для активной папки.

class NotesMasterDetailScreen extends StatefulWidget {
  NoteService? noteService;
  FolderService? folderService;

                      NotesMasterDetailScreen({
    super.key,
    this.noteService,
    this.folderService,
  });

  @override
  State<NotesMasterDetailScreen> createState() => _NotesMasterDetailScreenState();
}

class _NotesMasterDetailScreenState extends State<NotesMasterDetailScreen> {
  List<Note> _allNotes = []; // All notes for counting
  List<Note> _displayedNotes = []; // Notes for current view

  List<Folder> _folders = [];
  String? _selectedFolderId; // Null means all notes

          @override
  void initState() {
    super.initState();
    _loadNotes();
    _loadFolders();
  }

  Future<void> _loadNotes([String? folderId, String? sortBy]) async {
    print('[NotesMasterDetailScreen] _loadNotes Called with folderId: $folderId');
    try {
      // Always fetch all notes to update _allNotes for counting
      final allFetchedNotes = await widget.noteService!.getNotes(null); // Fetch all notes
      setState(() {
        _allNotes = allFetchedNotes;
      });

      // Fetch notes for the current view
      final displayedFetchedNotes = await widget.noteService!.getNotes(folderId, sortBy); // Pass sortBy
      setState(() {
        _displayedNotes = displayedFetchedNotes;
        print('[NotesMasterDetailScreen] _displayedNotes updated. Current count: ${_displayedNotes.length}');
      });
    } catch (e) {
      print('[NotesMasterDetailScreen] Перехвачена ошибка: $e');
    }
  }

  Future<void> _loadFolders() async {
    try {
      final fetchedFolders = await widget.folderService!.getFolders();
      setState(() {
        _folders = fetchedFolders;
      });
      // After loading folders, reload notes for the current selection to update counts
      await _loadNotes(_selectedFolderId);
    } catch (e) {
      print('[NotesMasterDetailScreen] Перехвачена ошибка при загрузке папок: $e');
    }
  }

  int _getNoteCountForFolder(String folderId) {
    return _allNotes.where((note) => note.folderId == folderId).length;
  }

  Future<void> _addNote() async {
    final result = await Navigator.of(context).push<Note>(
      MaterialPageRoute(
        builder: (context) => NoteEditorScreen(initialFolderId: _selectedFolderId),
      ),
    );

    if (result != null) {
      try {
        await widget.noteService!.createNote(result);
        _loadNotes(_selectedFolderId);
      } catch (e) {
        print('[NotesMasterDetailScreen] Перехвачена ошибка: $e');
      }
    }
  }

  Future<void> _deleteNote(String id) async {
    try {
      await widget.noteService!.deleteNote(id);
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
        await widget.noteService!.updateNote(result);
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
        await widget.folderService!.createFolder(folderName);
        _loadFolders(); // Refresh folder list
      } catch (e) {
        print('[NotesMasterDetailScreen] Ошибка при создании папки: $e');
      }
    }
  }

  void _showFolderOptionsMenu(BuildContext context, Folder folder) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext bc) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.edit_outlined, color: Colors.amber),
                title: const Text('Переименовать папку', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(bc); // Close bottom sheet
                  _renameFolder(folder);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.amber),
                title: const Text('Удалить папку', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(bc); // Close bottom sheet
                  _confirmDeleteFolder(context, folder); // Re-use existing delete logic
                },
              ),
              ListTile(
                leading: const Icon(Icons.sort_outlined, color: Colors.amber),
                title: const Text('Сортировать заметки', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(bc); // Close bottom sheet
                  _sortNotesInFolder(folder);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _confirmDeleteFolder(BuildContext context, Folder folder) {
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
              child: const Text('Удалить', style: TextStyle(color: Colors.amber)),
              onPressed: () async {
                Navigator.of(context).pop(); // Dismiss dialog
                try {
                  await widget.folderService!.deleteFolder(folder.id);
                  if (_selectedFolderId == folder.id) { // If the deleted folder was selected
                    setState(() {
                      _selectedFolderId = null; // Reset selection
                    });
                  }
                  _loadFolders(); // Refresh folder list (will also refresh notes for current selection)
                } catch (e) {
                  print('[NotesMasterDetailScreen] Ошибка при удалении папки: $e');
                }
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _renameFolder(Folder folder) async {
    String? newFolderName = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        String currentFolderName = folder.name;
        return AlertDialog(
          title: const Text('Переименовать папку'),
          content: TextField(
            controller: TextEditingController(text: currentFolderName),
            onChanged: (value) {
              currentFolderName = value;
            },
            decoration: const InputDecoration(hintText: 'Новое название папки'),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Отмена'),
              onPressed: () {
                Navigator.pop(context);
              },
            ),
            TextButton(
              child: const Text('Переименовать'),
              onPressed: () {
                Navigator.pop(context, currentFolderName);
              },
            ),
          ],
        );
      },
    );

    if (newFolderName != null && newFolderName.isNotEmpty && newFolderName != folder.name) {
      try {
        // Assuming FolderService has an updateFolder method
        // You might need to implement this in folder_service.dart and backend
        // For now, we'll just update locally and reload
        await widget.folderService!.updateFolder(folder.id, newFolderName); // This method needs to be implemented
        _loadFolders(); // Refresh folder list
      } catch (e) {
        print('[NotesMasterDetailScreen] Ошибка при переименовании папки: $e');
      }
    }
  }

  void _sortNotesInFolder(Folder folder) {
    // Implement sorting logic here
    // This could involve showing a dialog for sort options (e.g., by title, by date)
    // and then re-loading notes with a specific sort order. 
    print('[NotesMasterDetailScreen] Сортировка заметок в папке: ${folder.name}');
    // For now, just re-load notes to reflect any potential changes if sorting was implemented
    _loadNotes(folder.id);
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
              color: Colors.grey[800], // Darker grey background for folders
              border: Border(right: BorderSide(color: Colors.grey[300]!, width: 0.5)), // Subtle right border
            ),
            child: ListView(
              children: <Widget>[
                ListTile(
                  leading: const Icon(Icons.folder_open_outlined, color: Colors.amber),
                  title: Text('Все заметки (${_allNotes.length})', style: const TextStyle(fontSize: 16)),
                  onTap: () {
                    setState(() {
                      _selectedFolderId = null;
                    });
                    _loadNotes();
                  },
                ),
                const Divider(),
                ..._folders.map((folder) => ListTile(
                  leading: const Icon(Icons.folder_outlined, color: Colors.amber),
                  title: Text('${folder.name} (${_getNoteCountForFolder(folder.id)})', style: const TextStyle(fontSize: 16)),
                  trailing: IconButton( // Options icon
                    icon: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[700], // Background for the circle
                        shape: BoxShape.circle,
                      ),
                      padding: const EdgeInsets.all(4.0),
                      child: const Icon(Icons.more_horiz_outlined, color: Colors.amber), // Ellipsis icon
                    ),
                    onPressed: () {
                      // Show options menu
                      _showFolderOptionsMenu(context, folder);
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
                  leading: const Icon(Icons.create_new_folder_outlined, color: Colors.amber),
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
              color: Colors.grey[700], // Lighter gray background for notes list (same as scaffold)
              child: Scaffold(
                backgroundColor: Colors.grey[700], // Set background to match container
                key: ValueKey(_selectedFolderId ?? 'all_notes'), // Add a key to the Scaffold
                floatingActionButton: FloatingActionButton(
                  heroTag: 'notes-fab',
                  onPressed: _addNote,
                  tooltip: 'Новая заметка',
                  backgroundColor: Colors.amber, // Gold background
                  foregroundColor: Colors.black, // Black icon
                  shape: const CircleBorder(),
                  child: const Icon(Icons.note_add_outlined), // Changed icon to note_add
                ),
                body: _displayedNotes.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              'Здесь пока нет заметок.',
                              style: TextStyle(fontSize: 18, color: Colors.white),
                            ),
                            const SizedBox(height: 20),
                            ElevatedButton.icon(
                              onPressed: _addNote,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.amber, // Gold background
                                foregroundColor: Colors.black, // Black text/icon
                              ),
                              icon: const Icon(Icons.add_circle_outline),
                              label: const Text('Создать заметку'),
                            ),
                            if (_selectedFolderId == null) // Only show "Create Folder" if "All Notes" is selected
                              const SizedBox(height: 10),
                            if (_selectedFolderId == null) // Only show "Create Folder" if "All Notes" is selected
                              ElevatedButton.icon(
                                onPressed: _showCreateFolderDialog,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.amber, // Gold background
                                  foregroundColor: Colors.black, // Black text/icon
                                ),
                                icon: const Icon(Icons.create_new_folder_outlined),
                                label: const Text('Создать папку'),
                              ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        key: ValueKey(_displayedNotes.length.toString() + (_selectedFolderId ?? '')), // Keep this key
                        itemCount: _displayedNotes.length,
                        itemBuilder: (context, index) {
                          final note = _displayedNotes[index];
                          return Dismissible(
                            key: ValueKey(note.id),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              color: Colors.red,
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.symmetric(horizontal: 20.0),
                              child: const Icon(Icons.delete_outline, color: Colors.white),
                            ),
                            onDismissed: (direction) async {
                              final deletedNoteId = note.id;
                              setState(() {
                                _displayedNotes.removeWhere((n) => n.id == deletedNoteId); // Remove from local list immediately
                              });
                              try {
                                await widget.noteService!.deleteNote(deletedNoteId); // Delete from backend
                                await _loadFolders(); // Refresh folders; will also refresh notes for current selection
                              } catch (e) {
                                print('[NotesMasterDetailScreen] Ошибка при удалении заметки: $e');
                              }
                            },
                            child: ListTile(
                              tileColor: Colors.grey[700], // Set tile background color (same as scaffold)
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                              title: Text(note.title, style: const TextStyle(fontWeight: FontWeight.w500)),
                              subtitle: Text(note.content, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white)),
                              trailing: const Icon(Icons.arrow_forward_ios_outlined, size: 16.0, color: Colors.amber),
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

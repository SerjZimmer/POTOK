import 'package:flutter/material.dart';
import 'package:frontend/src/models/note.dart';
import 'package:frontend/src/models/folder.dart';
import 'package:frontend/src/services/folder_service.dart';

// NoteEditorScreen - это экран для создания новой и редактирования существующей заметки.
class NoteEditorScreen extends StatefulWidget {
  // Заметка для редактирования. Если null, экран находится в режиме создания.
  final Note? note;
  final String? initialFolderId; // Added this line

  // Конструктор принимает необязательный параметр note.
  const NoteEditorScreen({super.key, this.note, this.initialFolderId});

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  // TextEditingController используется для управления текстом в TextField.
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();

  final FolderService _folderService = FolderService();
  List<Folder> _folders = [];
  Folder? _selectedFolder;

  // Инициализируем состояние при первом создании виджета.
  @override
  void initState() {
    super.initState();
    // Если виджету была передана заметка, мы находимся в режиме редактирования.
    // Поэтому мы заполняем текстовые поля данными существующей заметки.
    if (widget.note != null) {
      _titleController.text = widget.note!.title;
      _contentController.text = widget.note!.content;
    }
    _loadFolders();
  }

  // Очищаем контроллеры при удалении виджета.
  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  // Строим UI для экрана редактора.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => Navigator.pop(context), // Go back
        ),
        // Динамически устанавливаем заголовок в зависимости от режима (создание или редактирование).
        title: Text(widget.note == null ? 'Новая заметка' : 'Редактировать', style: const TextStyle(color: Colors.black, fontSize: 17, fontWeight: FontWeight.w600)),
        // Добавляем кнопку сохранения на панель приложения.
        actions: [
          TextButton(
            onPressed: _saveNote, // При нажатии вызываем метод _saveNote.
            child: const Text('Сохранить', style: TextStyle(color: Colors.blueAccent, fontSize: 17, fontWeight: FontWeight.bold)),
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        // Используем Column для вертикального расположения текстовых полей.
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: DropdownButton<Folder>(
                isExpanded: true,
                value: _selectedFolder,
                hint: const Text('Выберите папку'),
                onChanged: (Folder? newValue) {
                  setState(() {
                    _selectedFolder = newValue;
                  });
                },
                items: _folders.map<DropdownMenuItem<Folder>>((Folder folder) {
                  return DropdownMenuItem<Folder>(
                    value: folder,
                    child: Text(folder.name),
                  );
                }).toList(),
              ),
            ),
            // TextField для заголовка заметки.
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                hintText: 'Заголовок',
                border: InputBorder.none, // Чистый вид без рамки.
                contentPadding: EdgeInsets.symmetric(vertical: 12.0),
              ),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8), // Небольшой отступ между полями.
            // TextField для содержимого заметки.
            Expanded(
              child: TextField(
                controller: _contentController,
                decoration: const InputDecoration(
                  hintText: 'Текст заметки',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 12.0),
                ),
                maxLines: null, // Позволяет вводить многострочный текст.
                expands: true,    // Заставляет TextField расширяться, чтобы заполнить доступное пространство.
              ),
            ),
          ],
        ),
      ),
    );
  }

  // _saveNote вызывается, когда пользователь нажимает кнопку сохранения.
  void _saveNote() {
    // Мы сохраняем только если заголовок не пуст.
    if (_titleController.text.isNotEmpty) {
      // Создаем объект Note с данными из текстовых полей.
      final result = Note(
        // Если мы редактируем, используем ID существующей заметки.
        id: widget.note?.id ?? '',
        title: _titleController.text,
        content: _contentController.text,
        folderId: _selectedFolder?.id ?? '',
      );
      // Закрываем текущий экран и возвращаем новую/обновленную заметку
      // в качестве результата. Предыдущий экран (NotesScreen) получит этот результат.
      Navigator.of(context).pop(result);
    }
  }

  Future<void> _loadFolders() async {
    try {
      final fetchedFolders = await _folderService.getFolders();
      setState(() {
        _folders = fetchedFolders;
        // Add "Uncategorized" option
        _folders.insert(0, Folder(id: '', name: 'Без папки')); // Add at the beginning

        if (widget.note != null && widget.note!.folderId.isNotEmpty) {
          _selectedFolder = _folders.firstWhere((folder) => folder.id == widget.note!.folderId);
        } else if (widget.initialFolderId != null) {
          _selectedFolder = _folders.firstWhere((folder) => folder.id == widget.initialFolderId);
        } else {
          // Default to "Uncategorized" if no specific folder is selected or provided
          _selectedFolder = _folders.firstWhere((folder) => folder.id == '');
        }
      });
    } catch (e) {
      print('Ошибка при загрузке папок: $e');
    }
  }
}

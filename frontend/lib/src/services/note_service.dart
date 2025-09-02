import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:frontend/src/models/note.dart';

/// NoteService — тонкий HTTP‑клиент для бэкенда Go.
///
/// Замечания:
/// - baseUrl обязательно со схемой (http://), иначе Uri.parse кинет ошибку
///   «No host specified…»;
/// - для Android‑эмулятора адрес бэкенда обычно 10.0.2.2:8080 → в будущем
///   вынести в конфиг по платформам.

class NoteService {
  final String baseUrl = 'http://localhost:8080'; // Base URL of your Go backend
  http.Client _client;

  NoteService({http.Client? client}) : _client = client ?? http.Client();

  set client(http.Client client) => _client = client;

  Future<List<Note>> getNotes([String? folderId, String? sortBy]) async {
    String path;
    Map<String, String> queryParams = {};

    if (folderId == null || folderId.isEmpty) {
      path = '/notes'; // Get all notes
    } else {
      path = '/folders/$folderId/notes'; // Get notes by folder
    }

    if (sortBy != null && sortBy.isNotEmpty) {
      queryParams['sort_by'] = sortBy;
    }

    final uri = Uri.parse('$baseUrl$path').replace(
      queryParameters: queryParams.isEmpty ? null : queryParams,
    );
    final response = await _client.get(uri);
    if (response.statusCode == 200) {
      print('Response body (getNotes): ${response.body}');
      Iterable list = json.decode(response.body);
      return list.map((model) => Note.fromJson(model)).toList();
    } else {
      print('Error: ${response.statusCode}');
      print('Response body: ${response.body}');
      throw Exception('Failed to load notes');
    }
  }

  Future<Note> createNote(Note note) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/notes'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(note.toJson()),
    );
    if (response.statusCode == 201) {
      return Note.fromJson(json.decode(response.body));
    } else {
      print('Error: ${response.statusCode}');
      print('Response body: ${response.body}');
      throw Exception('Failed to create note');
    }
  }

  Future<Note> updateNote(Note note) async {
    final response = await _client.put(
      Uri.parse('$baseUrl/notes/${note.id}'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(note.toJson()),
    );
    if (response.statusCode == 200) {
      return Note.fromJson(json.decode(response.body));
    } else {
      print('Error: ${response.statusCode}');
      print('Response body: ${response.body}');
      throw Exception('Failed to update note');
    }
  }

  Future<void> deleteNote(String id) async {
    final response = await _client.delete(Uri.parse('$baseUrl/notes/$id'));
    if (response.statusCode != 204) {
      print('Error: ${response.statusCode}');
      print('Response body: ${response.body}');
      throw Exception('Failed to delete note');
    }
  }
}

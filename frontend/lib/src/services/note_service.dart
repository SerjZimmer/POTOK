import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:frontend/src/models/note.dart';

class NoteService {
  final String baseUrl = 'localhost:8080'; // Base URL of your Go backend (host:port)

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

    final uri = Uri.http('localhost:8080', path, queryParams);
    final response = await http.get(uri);
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
    final response = await http.post(
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
    final response = await http.put(
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
    final response = await http.delete(Uri.parse('$baseUrl/notes/$id'));
    if (response.statusCode != 204) {
      print('Error: ${response.statusCode}');
      print('Response body: ${response.body}');
      throw Exception('Failed to delete note');
    }
  }
}
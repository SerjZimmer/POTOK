import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:frontend/src/models/note.dart';

class NoteService {
  final String baseUrl = 'http://localhost:8080'; // Base URL of your Go backend

  Future<List<Note>> getNotes([String? folderId]) async {
    String url;
    if (folderId == null || folderId.isEmpty) {
      url = '$baseUrl/notes'; // Get all notes
    } else {
      url = '$baseUrl/folders/$folderId/notes'; // Get notes by folder
    }
    final response = await http.get(Uri.parse(url));
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
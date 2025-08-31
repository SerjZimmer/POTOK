import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:frontend/src/models/folder.dart';

/// FolderService — HTTP‑клиент для операций с папками заметок.
///
/// Все методы бросают Exception при кодах ответа >= 400, чтобы UI мог
/// отобразить ошибку пользователю.

class FolderService {
  final String baseUrl = 'http://localhost:8080'; // Base URL of your Go backend

  Future<List<Folder>> getFolders() async {
    final response = await http.get(Uri.parse('$baseUrl/folders'));
    if (response.statusCode == 200) {
      Iterable list = json.decode(response.body);
      return list.map((model) => Folder.fromJson(model)).toList();
    } else {
      print('Error: ${response.statusCode}');
      print('Response body: ${response.body}');
      throw Exception('Failed to load folders');
    }
  }

  Future<Folder> createFolder(String name) async {
    final response = await http.post(
      Uri.parse('$baseUrl/folders'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'name': name}),
    );
    if (response.statusCode == 201) {
      return Folder.fromJson(json.decode(response.body));
    } else {
      print('Error: ${response.statusCode}');
      print('Response body: ${response.body}');
      throw Exception('Failed to create folder');
    }
  }

  Future<Folder> updateFolder(String id, String newName) async {
    final response = await http.put(
      Uri.parse('$baseUrl/folders/$id'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'name': newName}),
    );
    if (response.statusCode == 200) {
      return Folder.fromJson(json.decode(response.body));
    } else {
      print('Error: ${response.statusCode}');
      print('Response body: ${response.body}');
      throw Exception('Failed to update folder');
    }
  }

  Future<void> deleteFolder(String id) async {
    final response = await http.delete(Uri.parse('$baseUrl/folders/$id'));
    if (response.statusCode != 204) {
      print('Error: ${response.statusCode}');
      print('Response body: ${response.body}');
      throw Exception('Failed to delete folder');
    }
  }
}

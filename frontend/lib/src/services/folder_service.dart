import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:frontend/src/models/folder.dart';

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
}
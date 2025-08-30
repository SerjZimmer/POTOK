import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart'; // Добавляем для kDebugMode

class ApiService {
  // Базовый URL для вашего бэкенда.

  // Убедитесь, что он соответствует адресу, на котором запущен ваш Go-сервер.
  static const String baseUrl = 'http://localhost:8080'; // Без конечного слэша

  // Метод для выполнения GET-запросов.
  static Future<dynamic> get(String endpoint) async {
    final uri = Uri.parse('$baseUrl/$endpoint'); // Возвращаемся к Uri.parse
    if (kDebugMode) {
      print('[ApiService.get] Endpoint: $endpoint, URI: $uri');
    }
    final response = await http.get(uri);
    return _processResponse(response);
  }

  // Метод для выполнения POST-запросов.
  static Future<dynamic> post(String endpoint, Map<String, dynamic> data) async {
    final uri = Uri.parse('$baseUrl/$endpoint'); // Возвращаемся к Uri.parse
    if (kDebugMode) {
      print('[ApiService.post] Endpoint: $endpoint, URI: $uri');
    }
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: json.encode(data),
    );
    return _processResponse(response);
  }

  // Метод для выполнения PUT-запросов.
  static Future<dynamic> put(String endpoint, Map<String, dynamic> data) async {
    final uri = Uri.parse('$baseUrl/$endpoint'); // Возвращаемся к Uri.parse
    if (kDebugMode) {
      print('[ApiService.put] Endpoint: $endpoint, URI: $uri');
    }
    final response = await http.put(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: json.encode(data),
    );
    return _processResponse(response);
  }

  // Метод для выполнения DELETE-запросов.
  static Future<dynamic> delete(String endpoint) async {
    final uri = Uri.parse('$baseUrl/$endpoint'); // Возвращаемся к Uri.parse
    if (kDebugMode) {
      print('[ApiService.delete] Endpoint: $endpoint, URI: $uri');
    }
    final response = await http.delete(uri);
    return _processResponse(response);
  }

  // Вспомогательный метод для обработки ответов сервера.
  static dynamic _processResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      // Если ответ успешный, декодируем JSON и возвращаем его.
      if (response.body.isNotEmpty) {
        return json.decode(response.body);
      }
      return null; // Нет содержимого для 204 No Content и т.д.
    } else {
      // Если произошла ошибка, выбрасываем исключение.
      throw Exception('Ошибка API: ${response.statusCode} - ${response.body}');
    }
  }
}
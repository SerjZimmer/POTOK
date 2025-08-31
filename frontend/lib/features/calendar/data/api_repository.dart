import 'dart:convert';
import 'package:http/http.dart' as http;
import '../domain/entities.dart';

class ApiCalendarRepository {
  final String baseUrl;
  ApiCalendarRepository({this.baseUrl = 'http://localhost:8080'});

  Future<List<CalendarEntity>> listCalendars() async {
    final uri = Uri.parse('$baseUrl/v1/calendars');
    final res = await http.get(uri);
    if (res.statusCode != 200) throw Exception('listCalendars ${res.statusCode}');
    final body = json.decode(res.body) as Map<String, dynamic>;
    final items = (body['items'] as List?) ?? [];
    return items.map((e) => CalendarEntity.fromJson(e)).toList();
  }

  Future<CalendarEntity> createCalendar(String name, {String colorHex = '#FFC107', String tzidDefault = 'UTC'}) async {
    final uri = Uri.parse('$baseUrl/v1/calendars');
    final res = await http.post(uri, headers: {'Content-Type':'application/json'}, body: json.encode({
      'uid': '', 'name': name, 'colorHex': colorHex, 'tzidDefault': tzidDefault, 'isVisible': true
    }));
    if (res.statusCode != 201 && res.statusCode != 200) throw Exception('createCalendar ${res.statusCode}: ${res.body}');
    return CalendarEntity.fromJson(json.decode(res.body));
  }

  Future<CalendarEntity> updateCalendar(String uid, {String? name, String? colorHex, bool? isVisible, String? tzidDefault}) async {
    final uri = Uri.parse('$baseUrl/v1/calendars/$uid');
    final payload = <String, dynamic>{};
    if (name != null) payload['name'] = name;
    if (colorHex != null) payload['colorHex'] = colorHex;
    if (isVisible != null) payload['isVisible'] = isVisible;
    if (tzidDefault != null) payload['tzidDefault'] = tzidDefault;
    final res = await http.patch(uri, headers: {'Content-Type':'application/json'}, body: json.encode(payload));
    if (res.statusCode != 200) {
      throw Exception('updateCalendar ${res.statusCode}: ${res.body}');
    }
    return CalendarEntity.fromJson(json.decode(res.body));
  }

  Future<EventEntity> createEvent(EventEntity e) async {
    final uri = Uri.parse('$baseUrl/v1/events');
    final res = await http.post(uri, headers: {'Content-Type':'application/json'}, body: json.encode(_eventToJson(e)));
    if (res.statusCode != 201 && res.statusCode != 200) throw Exception('createEvent ${res.statusCode}: ${res.body}');
    return EventEntity.fromJson(json.decode(res.body));
  }

  Future<EventEntity> updateEvent(EventEntity e) async {
    final uri = Uri.parse('$baseUrl/v1/events/${e.uid}');
    final res = await http.patch(uri, headers: {'Content-Type':'application/json'}, body: json.encode(_eventToJson(e)));
    if (res.statusCode != 200) throw Exception('updateEvent ${res.statusCode}: ${res.body}');
    return EventEntity.fromJson(json.decode(res.body));
  }

  Future<void> deleteEvent(String uid) async {
    final uri = Uri.parse('$baseUrl/v1/events/$uid');
    final res = await http.delete(uri);
    if (res.statusCode != 204) throw Exception('deleteEvent ${res.statusCode}: ${res.body}');
  }

  Future<List<EventEntity>> expand(DateTime start, DateTime end, {List<String>? calendarUids, String? q}) async {
    final qs = <String, String>{
      'timeMin': start.toUtc().toIso8601String(),
      'timeMax': end.toUtc().toIso8601String(),
    };
    if (q != null && q.isNotEmpty) qs['q'] = q;
    Uri uri = Uri.parse('$baseUrl/v1/events/expand').replace(queryParameters: qs);
    if (calendarUids != null && calendarUids.isNotEmpty) {
      final params = Map<String, dynamic>.from(uri.queryParameters);
      final pairs = [
        'timeMin=${Uri.encodeQueryComponent(qs['timeMin']!)}',
        'timeMax=${Uri.encodeQueryComponent(qs['timeMax']!)}',
        if (q != null && q.isNotEmpty) 'q=${Uri.encodeQueryComponent(q)}',
        for (final c in calendarUids) 'calendarUid=${Uri.encodeQueryComponent(c)}'
      ];
      uri = Uri.parse('${uri.scheme}://${uri.host}:${uri.port}${uri.path}?${pairs.join('&')}');
    }
    final res = await http.get(uri);
    if (res.statusCode != 200) throw Exception('expand ${res.statusCode}: ${res.body}');
    final body = json.decode(res.body) as Map<String, dynamic>;
    final items = (body['items'] as List?) ?? [];
    return items.map((e) => EventEntity.fromJson(e)).toList();
  }

  Future<void> apply(String uid, {required String action, required String scope, String? recurrenceId, Map<String, dynamic>? patch}) async {
    final uri = Uri.parse('$baseUrl/v1/events/$uid:apply');
    final payload = {
      'action': action,
      'scope': scope,
      if (recurrenceId != null) 'recurrenceId': recurrenceId,
      if (patch != null) 'patch': patch,
    };
    final res = await http.post(uri, headers: {'Content-Type':'application/json'}, body: json.encode(payload));
    if (res.statusCode != 200) throw Exception('apply ${res.statusCode}: ${res.body}');
  }

  Map<String, dynamic> _eventToJson(EventEntity e) => e.toJson();
}

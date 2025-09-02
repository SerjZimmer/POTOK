
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/app/main.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:frontend/src/services/note_service.dart';
import 'package:frontend/src/services/folder_service.dart';

void main() {
  testWidgets('AppShell has a BottomNavigationBar with two items', (WidgetTester tester) async {
    final mockClient = MockClient((request) async {
      if (request.url.path == '/folders') {
        return http.Response('[]', 200);
      }
      if (request.url.path == '/notes') {
        return http.Response('[]', 200);
      }
      return http.Response('Not Found', 404);
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<http.Client>.value(
            value: mockClient,
          ),
          Provider<NoteService>(
            create: (context) => NoteService(client: context.read<http.Client>()),
          ),
          Provider<FolderService>(
            create: (context) => FolderService(client: context.read<http.Client>()),
          ),
        ],
        child: const MaterialApp(home: AppShell()),
      ),
    );

    expect(find.byType(BottomNavigationBar), findsOneWidget);
    expect(find.byIcon(Icons.notes), findsOneWidget);
    expect(find.byIcon(Icons.calendar_today), findsOneWidget);
  });
}

// Импортируем необходимые пакеты из Flutter.
import 'package:flutter/material.dart';
import 'package:flutter/material.dart';
import 'package:frontend/notes_master_detail_screen.dart';

// main - главная точка входа во Flutter-приложение.
void main() {
  runApp(const MyApp());
}

// MyApp - корневой виджет приложения.
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // Этот метод строит дерево виджетов для корневого элемента.
  @override
  Widget build(BuildContext context) {
    // MaterialApp - удобный виджет, который включает в себя ряд виджетов,
    // обычно требуемых для приложений в стиле Material Design.
    return MaterialApp(
      title: 'ПОТОК', // Название приложения (используется ОС).
      theme: ThemeData(
        primarySwatch: Colors.blueGrey, // Более нейтральный цвет
        visualDensity: VisualDensity.adaptivePlatformDensity, // Адаптирует UI к платформе.
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
          titleTextStyle: TextStyle(color: Colors.black, fontSize: 22, fontWeight: FontWeight.bold),
        ),
      ),
      // Свойство home устанавливает маршрут по умолчанию для приложения.
      home: const NotesMasterDetailScreen(),
    );
  }
}
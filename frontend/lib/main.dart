// Импортируем необходимые пакеты из Flutter.
import 'package:flutter/material.dart';
import 'package:flutter/material.dart';
import 'package:frontend/app/main.dart';

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
    // MaterialApp — корневой Material-контейнер приложения.
    // Здесь задается тема (темная), общие стили и стартовый экран AppShell.
    return MaterialApp(
      title: 'ПОТОК', // Название приложения (используется ОС).
      theme: ThemeData(
        brightness: Brightness.dark, // Dark theme
        scaffoldBackgroundColor: Colors.grey[700]!, // Lighter gray background
        primaryColor: Colors.amber, // Set primary color to gold
        visualDensity: VisualDensity.adaptivePlatformDensity,
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.grey[800], // Dark gray app bar
          foregroundColor: Colors.white, // White text/icons
          elevation: 0, // Add shadow for separation
          titleTextStyle: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold), // White title
        ),
        textTheme: const TextTheme(
          displayLarge: TextStyle(color: Colors.white),
          displayMedium: TextStyle(color: Colors.white),
          displaySmall: TextStyle(color: Colors.white),
          headlineLarge: TextStyle(color: Colors.white),
          headlineMedium: TextStyle(color: Colors.white),
          headlineSmall: TextStyle(color: Colors.white),
          titleLarge: TextStyle(color: Colors.white),
          titleMedium: TextStyle(color: Colors.white),
          titleSmall: TextStyle(color: Colors.white),
          bodyLarge: TextStyle(color: Colors.white),
          bodyMedium: TextStyle(color: Colors.white),
          bodySmall: TextStyle(color: Colors.white),
          labelLarge: TextStyle(color: Colors.white),
          labelMedium: TextStyle(color: Colors.white),
          labelSmall: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(
          color: Colors.amber, // Gold icons
        ),
        dividerColor: Colors.grey, // Grey dividers
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Colors.amber, // Gold background
          foregroundColor: Colors.black, // Black icon
        ),
      ),
      // Свойство home устанавливает маршрут по умолчанию для приложения — AppShell
      // с нижней навигацией по разделам.
      home: const AppShell(),
    );
  }
}

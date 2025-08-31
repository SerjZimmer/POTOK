import 'package:flutter/material.dart';

// Определяем пользовательский основной цвет
const MaterialColor primaryColor = MaterialColor(
  _primaryColorValue,
  <int, Color>{
    50: Color(0xFFFFFDE7),
    100: Color(0xFFFFF9C4),
    200: Color(0xFFFFF59D),
    300: Color(0xFFFFF176),
    400: Color(0xFFFFEE58),
    500: Color(_primaryColorValue), // #f5cb41
    600: Color(0xFFFACC39),
    700: Color(0xFFF8C030),
    800: Color(0xFFF5B627),
    900: Color(0xFFF0A31A),
  },
);
const int _primaryColorValue = 0xFFF5CB41;

// Определяем пользовательскую тему
ThemeData buildAppTheme() {
  return ThemeData(
    brightness: Brightness.light, // Светлая тема согласно дизайну
    scaffoldBackgroundColor: Colors.grey[800], // Более темный фон для области заметок
    primaryColor: primaryColor,
    visualDensity: VisualDensity.adaptivePlatformDensity,
    appBarTheme: AppBarTheme( // Удалено const
      backgroundColor: Colors.grey[50], // bg-gray-50 для панели приложения
      foregroundColor: Colors.grey[800], // text-gray-800 для иконок/текста
      elevation: 0,
      titleTextStyle: TextStyle(color: Colors.grey[900], fontSize: 20, fontWeight: FontWeight.bold), // text-gray-900
    ),
    textTheme: TextTheme(
      displayLarge: TextStyle(color: Colors.grey[900]),
      displayMedium: TextStyle(color: Colors.grey[900]),
      displaySmall: TextStyle(color: Colors.grey[900]),
      headlineLarge: TextStyle(color: Colors.grey[900]),
      headlineMedium: TextStyle(color: Colors.grey[900]),
      headlineSmall: TextStyle(color: Colors.grey[900]),
      titleLarge: TextStyle(color: Colors.grey[900]),
      titleMedium: TextStyle(color: Colors.grey[900]),
      titleSmall: TextStyle(color: Colors.grey[900]),
      bodyLarge: TextStyle(color: Colors.grey[800]), // text-gray-800
      bodyMedium: TextStyle(color: Colors.grey[800]),
      bodySmall: TextStyle(color: Colors.grey[800]),
      labelLarge: TextStyle(color: Colors.grey[800]),
      labelMedium: TextStyle(color: Colors.grey[800]),
      labelSmall: TextStyle(color: Colors.grey[800]),
    ),
    iconTheme: IconThemeData(
      color: Colors.grey[800], // Цвет иконки по умолчанию
    ),
    dividerColor: Colors.grey[300], // border-gray-300 для разделителей
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: primaryColor, // основной цвет
      foregroundColor: Colors.black, // черный текст
    ),
    cardTheme: CardThemeData( // Изменено на CardThemeData
      color: Colors.grey[800], // Более темный фон для карточек
      elevation: 1, // тень-sm
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8.0), // скругленный-lg
        side: BorderSide(color: Colors.grey[200]!), // border-gray-200
      ),
    ),
    listTileTheme: ListTileThemeData(
      selectedTileColor: Colors.grey[300], // bg-gray-300 для выбранной папки
      // hover:bg-gray-300 - Удалено
    ),
  );
}

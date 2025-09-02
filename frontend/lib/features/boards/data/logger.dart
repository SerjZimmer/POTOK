import 'package:flutter/foundation.dart';

class BoardsLogger {
  static String _ts() => DateTime.now().toIso8601String();

  static void info(String message, {Map<String, Object?> ctx = const {}}) {
    final c = ctx.isEmpty ? '' : ' | ${_fmt(ctx)}';
    debugPrint('[Доски][INFO ][${_ts()}] $message$c');
  }

  static void warn(String message, {Map<String, Object?> ctx = const {}}) {
    final c = ctx.isEmpty ? '' : ' | ${_fmt(ctx)}';
    debugPrint('[Доски][WARN ][${_ts()}] $message$c');
  }

  static void error(String message, {Object? error, Map<String, Object?> ctx = const {}}) {
    final c = ctx.isEmpty ? '' : ' | ${_fmt(ctx)}';
    final e = error == null ? '' : ' | error=$error';
    debugPrint('[Доски][ERROR][${_ts()}] $message$c$e');
  }

  static String _fmt(Map<String, Object?> ctx) {
    return ctx.entries.map((e) => '${e.key}=${e.value}').join(', ');
  }
}


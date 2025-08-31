# POTOK — Frontend

Flutter 3.x приложение (Dark theme). Модуль «Заметки» + «Календарь» (MVP офлайн‑первый).

## Запуск

1) Backend: `make run-backend`
2) Frontend: `cd frontend && make run` (или `flutter run -d chrome`)

## Календарь (MVP)

- Bottom Navigation: переключение между «Заметками» и «Календарём».
- Экран календаря: заглушки для представлений Month/Week/3-Day/Day/Agenda, согласованные с текущей темой.
- Data-слой (заготовка): `lib/features/calendar/data/repository.dart` — интерфейсы для Drift/FTS5, soft-delete и напоминаний.
- RRULE сервис: `lib/features/calendar/services/rrule_service.dart` — прототип API (парсинг/сборка/экспансия).
- Тесты: `test/calendar_rrule_test.dart`.

## Следующие шаги

- Добавить зависимости (flutter_riverpod, drift, timezone, flutter_local_notifications, dio/openapi client) в `pubspec.yaml` и реализовать репозитории и изоляты.
- Сгенерировать REST‑клиент из `openapi/calendar.yaml` (dart‑dio). Пока сеть не используется, интерфейсы зафиксированы.

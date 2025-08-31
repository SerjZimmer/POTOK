# Дорожная карта: Календарь (Offline → Online)

Документ описывает архитектурное видение и поэтапный план развития календаря от текущего офлайн‑MVP до промышленной онлайн‑системы с CalDAV/iTIP/iMIP, Free/Busy, масштабированием до 200 000 активных пользователей.

## 0. Текущее состояние (MVP, офлайн)

- Клиент: Flutter 3.x, модуль «Календарь» с представлениями Month/Week/3‑Day/Day/Agenda.
- Локальное хранилище: JSON‑файл `~/.potok_calendar.json` (будет заменено на Drift).
- RRULE: поддержка частых паттернов (DAILY/WEEKLY/MONTHLY/YEARLY, INTERVAL, BYDAY, BYMONTHDAY, BYMONTH, UNTIL/COUNT, позиционный BYDAY в MONTHLY, EXDATE). Экспансия — в видимом окне.
- Операции серий: «только это» (override + EXDATE), «это и все последующие» (split RRULE), «вся серия».
- OpenAPI: `openapi/calendar.yaml` (источник правды), backend‑заглушки на /v1/*.

Ограничения: нет Drift/FTS5, нет Riverpod, нет уведомлений/TZ, нет онлайн‑синхронизации, нет drag‑create/resize, нет раскладки перекрытий.

Как это работает сейчас (разделение ответственности)

- Фронтенд (Flutter)
  - Экран «Календарь» содержит только UI/навигацию между представлениями (Месяц/Неделя/3‑Дня/День/Список).
  - Для загрузки событий вызывает серверный `GET /v1/events/expand` с окном времени (например, видимые 5–6 недель месяца или 7 дней недели, 1 день и т. п.).
  - Для CRUD и операций над серией вызывает REST:
    - POST/GET/PATCH/DELETE `/v1/events` — базовые сущности.
    - POST `/v1/events/{uid}:apply` — `action=update|delete`, `scope=this|following|series`, `recurrenceId`, `patch`.
  - Фронт НЕ разворачивает RRULE и НЕ управляет EXDATE/override: только отправляет команды и отрисовывает полученные инстансы.

- Бэкенд (Go, SQLite)
  - Серверная экспансия RRULE (DAILY/WEEKLY/MONTHLY/YEARLY, INTERVAL, BYDAY/позиционный BYDAY, BYMONTHDAY, BYMONTH, COUNT/UNTIL), учет EXDATE и подмена override‑инстансов.
  - Серверные операции над сериями: delete/this (EXDATE), delete/following (split RRULE, удаление хвоста override’ов), update/this (override), update/following (split+новая серия), update/series (PATCH).
  - Все времена в UTC (RFC3339). Окно — полуинтервал [start,end).
  - Хранение: таблицы calendars/events/event_overrides/event_exdates; индексы под expand/apply.

---

## 1. Ближайшие офлайн‑шаги (Drift + Riverpod)

Цель: надёжная офлайн‑база, производительность, подготовка к синку.

- Хранилище: Drift (SQLite) + FTS5
  - Таблицы: `calendars`, `events`, `reminders`, `overrides` (или объединённо в `events` с parentUid/recurrenceId), `sync_state`.
  - Индексы: по `calendarUid`, `startUtc`, `endUtc`, `updatedAt`, FTS по `title/description/location`.
  - Миграции: V1 → V2 (перенос из JSON), стратегии миграции/отката.
- Состояние: Riverpod
  - Провайдеры для текущего диапазона, фильтров, поиска.
  - Кэширование: LRU по расширенным инстансам (expanded occurrences) в памяти.
- RRULE‑движок
  - Изолят для экспансии тяжёлых серий.
  - Позиционные правила: поддержка множественного BYDAY/BYMONTHDAY.
  - Кэш на уровне «(seriesUid, window) → list<DateTime>».
- Presentation
  - Drag‑create/resize в Day/Week/3‑Day.
  - Лэйаут перекрытий (greedy + compaction, как у Google Calendar).
  - Линия «текущее время», быстрые пресеты длительности.
  - Автонавигация «Сегодня»/«К текущему времени».
- Напоминания (локальные)
  - `flutter_local_notifications`; хранилище `reminders` с offsetMinutes, метод=notification.
  - Планировщик фоновых задач (на мобильных + desktop).
- Timezone
  - `timezone` пакет; хранить tzid в событиях и в календаре по умолчанию.
  - Конверсия времени для all‑day/многодневных.

Результат: офлайн‑календарь уровня «ежедневное использование», готовый к синку.

---

## 2. Онлайн‑синхронизация (REST/OpenAPI → CalDAV/iTIP)

Цель: синхронность между устройствами, интеграции, импорт/экспорт.

### 2.1. Слой синхронизации REST (по OpenAPI)

- Протокол
  - Cursor/anchor delta stream: `GET /v1/sync/delta?anchor&limit&cursor` → `{items,nextCursor,newAnchor}`.
  - Типы патчей: `upsert(calendar/event/reminder)`, `delete(uid,type,deletedAt)`.
  - Идемпотентность: `Idempotency-Key` для POST; `ETag` + `If-Match`/`If-None-Match`.
- Конфликты
  - Политика по умолчанию: last‑writer‑wins (по `updatedAt` + `ETag`).
  - Advanced: выборочно CRDT‑подход для полей описания (будущее).
- Обновления клиента
  - Фоновая синхронизация; слияние локальных/удалённых изменений.
  - Журнал изменений: таблица `sync_state` (последний anchor, положения курсоров). 
- Безопасность
  - JWT/OAuth2 (по мере появления учёток), TLS, rate‑limits.

### 2.2. Поддержка RFC и интеграций

- RFC 5545 iCalendar: полная поддержка RRULE/EXDATE/RECURRENCE‑ID/DTSTART/DTEND.
- RFC 5546 iTIP: приглашения/ответы (ACCEPTED/TENTATIVE/DECLINED), обновления серии/инстансов.
- RFC 6047 iMIP: доставка приглашений по email (интеграция с почтовым модулем).
- RFC 7808 Time Zone Data Service: загрузка актуальных IANA TZ.
- RFC 5545 Free/Busy: публикация `VFREEBUSY`, агрегация занятости.
- CalDAV (RFC 4791) и WebDAV (RFC 4918)
  - Эндпоинт CalDAV‑сервера: коллекции по аккаунту/календарю.
  - Аутентификация: Basic+TLS на MVP, затем OAuth2.
  - Сервер хранит `VEVENT` как `.ics` или нормализованные записи в БД; отвечает REPORT запросами по диапазону, поддерживает `sync-collection`.
  - CardDAV (RFC 6352) — для будущих контактов (общие ресурсы: адресаты, организаторы, iMIP).

### 2.3. Импорт/экспорт

- ICS импорт: парсер .ics (в том числе многообъектные файлы), маппинг в события и overrides.
- ICS экспорт: выбор календаря/диапазона, генерация `VCALENDAR` c `VEVENT`.

---

## 3. Серверная архитектура (онлайн, масштаб до 200 000 пользователей)

### 3.1. Ядро

- Язык/фреймворк: Go 1.22+, chi, контекст везде, middleware (request‑id, logging, metrics, auth, rate‑limit).
- Хранилище: PostgreSQL 15+
  - Схема: `calendars`, `events`, `event_overrides`, `reminders`, `attendees`, `freebusy_slots`, `users`, `devices`, `sync_cursors`.
  - Индексы: `events(calendar_uid,start_utc)`, GIN по FTS; партиционирование по месяцу (`start_utc`) для событий.
  - Триггеры/функции: пересчёт `updated_at`, генерация `etag`.
- Поиск: PostgreSQL FTS или Meilisearch/Elasticsearch (при росте).
- Очередь: NATS/Kafka для фоновых задач (уведомления, рассылка приглашений, Free/Busy агрегация).
- Кэш: Redis/KeyDB для сессий, краткоживущих кэшей и rate‑limits.
- Хранилище файлов (вложения приглашений, ICS): S3‑совместимый (MinIO/S3/GCS).

### 3.2. Free/Busy

- Источник истины: события со статусами и участниками.
- Агрегация: материализованные окна по пользователю/календарю (например, store «занятости» на 90 дней вперёд, обновление по триггерам/очереди).
- API: `GET /v1/freebusy?users[]=...&timeMin&timeMax` → слоты «busy» (и «tentative», если нужно).

### 3.3. Нагрузочные цели

- Профиль: 200k MAU, пик одновременных соединений 10–20k, запись/сек ~1–2k.
- Практики:
  - Индексация по диапазонам времени;
  - Партиционирование по `start_utc` (месяц/квартал);
  - Горизонтальное масштабирование API (stateless узлы за LB);
  - Бэкенд‑пулы соединений, read‑replica для тяжёлых списков;
  - Наблюдаемость: Prometheus + Grafana, structured logs, трассировка (OTel);
  - Тесты производительности: k6/Vegeta сценарии (списки, синк, freebusy).

---

## 4. Клиент: UX и расширения

- Drag‑create/resize: интерактивное изменение длительности с привязкой к сетке.
- Раскладка перекрытий: компоновка по столбцам (line sweep + greedy) в Day/Week.
- Блокировки конфликтов: на уровне UI предупреждать об изменениях «вне окна».
- Поиск и фильтры: FTS, фильтр по календарям/цветам, диапазону, участникам (в будущем).
- Мультикалендари: цвета, видимость, порядок, быстрые переключатели.
- Нотификации: локальные и push (после появления сервера + токенов устройств).

---

## 5. План релизов (этапы)

1) Drift + Riverpod + FTS5, RRULE полная, Day/Week UX, локальные напоминания и TZ.
2) REST‑синхронизация (anchors, delta, ETag), авторизация, базовые метрики.
3) iTIP/iMIP, приглашения по email, Free/Busy.
4) CalDAV сервер, внешние клиенты (Apple/Thunderbird/Outlook с плагинами).
5) Масштабирование: PostgreSQL партиции, очереди, кэш, поиск, observability.
6) Полировка UX, офлайн‑мёрджи, диффы на уровне полей, push‑синк.

---

## 6. Риски и смягчение

- Сложность RRULE: использовать battle‑tested библиотеки для критичных участков, собственный слой — через изолят + тесты на наборах из RFC.
- Конфликты при синке: предусмотреть политику для каждой сущности, лог аудита для разборов.
- Масштабируемость: раннее проектирование партиций и индексов, нагрузочные тесты до релиза.
- TZ/All‑day: строгие правила интерпретации (локальная TZ календаря), тестовые наборы переходов.

POTOK — Календарь: архитектура и логика

Назначение

Календарь реализован по принципу «тонкий фронт / умный бэкенд». Вся бизнес‑логика повторов (RRULE), исключений (EXDATE), переопределений отдельных повторений (override, RECURRENCE‑ID) и операции над сериями выполняются на сервере. Клиент (Flutter) отвечает только за отображение и отправку команд.

Слои

- HTTP (chi): backend/internal/calendar/http
  - /v1/events/expand — серверная экспансия инстансов событий в окне времени [timeMin, timeMax) (полуинтервал).
  - /v1/events/{eventUid}:apply — «скоупленные» операции над сериями: action=update|delete, scope=this|following|series, recurrenceId, patch.
  - CRUD: /v1/calendars, /v1/events — создание/чтение/изменение/удаление базовых сущностей.

- Service: backend/internal/calendar/service
  - SQLite‑реализация (sqlite.go): EventService/CalendarService поверх существующего SQLite‑подключения.
  - In‑memory‑реализация (memory.go): облегчённая версия для тестов/черновиков.
  - Основные методы EventService:
    - Expand(ctx, timeMinISO, timeMaxISO, calendarUids[], q) → []Event
    - Apply(ctx, uid, action, scope, recurrenceId, patch) → interface{}

- RRULE: backend/internal/calendar/rrule
  - ExpandOccurrences(spec, windowStart, windowEnd) — разворачивает серию в окне (UTC, полуинтервал).
  - WithUntil(rule, until) — возвращает RRULE с UNTIL; удаляет COUNT.

Модель данных (SQLite)

- calendars(uid, name, color_hex, is_visible, tzid_default, created_at, updated_at, deleted_at)
- events(uid, calendar_uid, title, description, location, start_utc, end_utc, is_all_day, tzid, recurrence_rule, created_at, updated_at, deleted_at)
- event_overrides(id, parent_uid, recurrence_id, title?, description?, location?, start_utc?, end_utc?, is_all_day?, tzid?, deleted_at?)
- event_exdates(parent_uid, exdate)
- Индексы: events(calendar_uid, start_utc), events(updated_at), event_overrides(parent_uid, recurrence_id), event_exdates(parent_uid, exdate)

Ключевая логика

1) Экспансия инстансов (Expand)

- Клиент запрашивает окно [timeMin, timeMax) для нужного представления (месяц/неделя/день).
- Сервис:
  1. Выбирает из БД базовые события: одиночные, пересекающие окно, и все повторяющиеся (с RRULE).
  2. Для каждой серии подгружает EXDATE и overrides.
  3. Разворачивает RRULE с помощью rrule.ExpandOccurrences (UTC, полуинтервал), фильтрует EXDATE, подменяет инстансы override‑ами.
- Результат — плоский список Event с заполненными ParentUID/RecurrenceID у инстансов.

Поддерживаемые правила (MVP): DAILY/WEEKLY/MONTHLY/YEARLY, INTERVAL, BYDAY (в WEEKLY и позиционный в MONTHLY: 1MO/-1SU), BYMONTHDAY, BYMONTH, COUNT/UNTIL, EXDATE.

2) Операции над сериями (Apply)

- delete/series — помечает базовое событие как удалённое (soft delete).
- delete/this — записывает EXDATE (скрывает ровно один инстанс).
- delete/following — «режет» серию: обновляет RRULE (UNTIL = recurrenceId−1с), удаляет overrides на и после точки split.
- update/series — частично обновляет базовую запись (PATCH).
- update/this — upsert override (индивидуальные изменения выбранного инстанса).
- update/following — режет серию и создаёт новую серию «на хвосте», применяя поля из patch.

Инварианты и договорённости

- Все времена в БД — в RFC3339 (UTC). Клиент конвертирует туда/обратно.
- Окно экспансии — полуинтервал [start, end) для предсказуемости.
- Клиент не реализует логику RRULE/EXDATE/override — только UI и REST.

Тесты

- Юнит‑тесты на RRULE: backend/internal/calendar/rrule/rrule_test.go (табличные примеры).
- Юнит‑тесты на SQLite‑сервис: backend/internal/calendar/service/sqlite_test.go — EXDATE, override «только это», split «последующие», WEEKLY (BYDAY), MONTHLY (позиционный BYDAY), YEARLY (BYMONTH/BYMONTHDAY) и др.

Производительность и индексация

- Индексы по calendar_uid/start_utc, updated_at, parent_uid/recurrence_id и EXDATE ускоряют выборку кандидатов и замену инстансов.
- Экспансия выполняется строго в окне — это ключ к масштабируемости даже при «бесконечных» сериях (UNTIL/COUNT ограничиваются на уровне формы клиента; сервер всё равно работает в окне).


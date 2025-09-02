Модуль «Доски» (Kanban/Scrum)

Назначение

Модуль предоставляет REST‑API и хранение для управления задачами по аналогии с Jira (Kanban/Scrum): проекты/доски, колонки/статусы, задачи, перетаскивание между колонками, базовый CSV импорт/экспорт. Интеграции: связь с заметками, автосоздание событий календаря по due date.

Архитектура

- HTTP: internal/boards/http/router.go
  - /v1/boards (GET/POST)
  - /v1/boards/{boardId}/columns (GET/POST)
  - /v1/boards/{boardId}/issues (GET/POST)
  - /v1/issues/{issueId}:move (POST)
  - /v1/boards/{boardId}/export.csv (GET)
  - /v1/boards/{boardId}/import.csv (POST)

- Service: internal/boards/service/sqlite.go
  - BoardService(List/Create/AddColumn/ListColumns)
  - IssueService(Create/ListByBoard/Move)
  - Инварианты:
    - Позиции карточек — целые; при перемещении position задаётся клиентом (MVP).
    - При создании issue с due_date автоматически создаётся событие в календаре (UTC, 1 час, title: «Due: …»).
    - Возможна связь с заметкой (note_id).

- DB: см. internal/db/database.go
  - boards, board_columns, issues, issue_comments, sprints.
  - Индексы: issues(board_id,column_id), issues(due_date).

Интеграции

- Календарь: при due_date создаётся запись в events (см. service/sqlite.go).
- Заметки: в поле note_id можно хранить id заметки.

Планы развития

- Полноценная поддержка Scrum: backlog, спринты (start/close), перенос задач, velocity.
- Ограничения WIP, сортировки/фильтры/поиск (FTS), вложения/комментарии с авторством.
- Перестройка позиций по алгоритму (gap/batch renumber).
- OpenAPI спецификация модулю «Доски» и генерация клиентов.


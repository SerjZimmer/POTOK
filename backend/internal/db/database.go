package db

import (
    "database/sql"
    "fmt"
    "log/slog"
    "strings"

    _ "github.com/mattn/go-sqlite3"
)

// InitDB инициализирует базу данных SQLite и создает/обновляет таблицы.
func InitDB(filepath string) (*sql.DB, error) {
	// Используем DSN, чтобы применить настройки ко всем соединениям пула
	dsn := fmt.Sprintf("file:%s?_busy_timeout=5000&_foreign_keys=on&_journal_mode=WAL&_synchronous=NORMAL", filepath)
	db, err := sql.Open("sqlite3", dsn)
	if err != nil {
		slog.Error("DB: Ошибка при открытии базы данных", "error", err)
		return nil, err
	}
	// Ограничиваем пул до одного открытого соединения — для SQLite это безопаснее
	db.SetMaxOpenConns(1)
	db.SetMaxIdleConns(1)
	db.SetConnMaxLifetime(0)

	// Дублируем PRAGMA на текущем соединении (полезно при первом создании файла)
	if _, err := db.Exec("PRAGMA journal_mode=WAL;"); err != nil {
		slog.Warn("DB: Не удалось установить journal_mode=WAL", "error", err)
	}
	if _, err := db.Exec("PRAGMA synchronous=NORMAL;"); err != nil {
		slog.Warn("DB: Не удалось установить synchronous=NORMAL", "error", err)
	}
	if _, err := db.Exec("PRAGMA busy_timeout=5000;"); err != nil {
		slog.Warn("DB: Не удалось установить busy_timeout", "error", err)
	}
	if _, err := db.Exec("PRAGMA foreign_keys=ON;"); err != nil {
		slog.Warn("DB: Не удалось включить foreign_keys", "error", err)
	}
	// Создаем таблицу для папок
	foldersQuery := `
	CREATE TABLE IF NOT EXISTS folders (
		id TEXT PRIMARY KEY,
		name TEXT NOT NULL
	);`
	_, err = db.Exec(foldersQuery)
	if err != nil {
		slog.Error("DB: Ошибка при создании таблицы 'folders': %v", "error", err)
		return nil, err
	}

    // Создаем таблицу для заметок (если ее нет)
    notesQuery := `
    CREATE TABLE IF NOT EXISTS notes (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        folder_id TEXT NOT NULL,
        created_at TEXT,
        FOREIGN KEY(folder_id) REFERENCES folders(id)
    );`

	// Примечание: В реальном приложении для изменения существующей таблицы
	// лучше использовать полноценную систему миграций.
	// Здесь для простоты мы просто создаем таблицу с новой схемой.
	// Старая таблица notes без folder_id вызовет ошибку при добавлении внешнего ключа.
	// Для учебного проекта проще удалить старый файл potok.db

    _, err = db.Exec(notesQuery)
    if err != nil {
        slog.Error("DB: Ошибка при создании таблицы 'notes': %v", "error", err)
        return nil, err
    }

    // --- Календарь (MVP) ---
    // Таблицы ниже проектируются с учётом будущего перехода на PostgreSQL.
    // Храним времена в RFC3339 (TEXT) — это упрощает межъязыковую сериализацию,
    // при миграции в PG поля станут TIMESTAMP WITH TIME ZONE.
    calendarsQuery := `
    CREATE TABLE IF NOT EXISTS calendars (
        uid TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        color_hex TEXT NOT NULL,
        is_visible INTEGER NOT NULL DEFAULT 1,
        tzid_default TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT
    );`
    if _, err := db.Exec(calendarsQuery); err != nil {
        slog.Error("DB: Ошибка при создании таблицы 'calendars'", "error", err)
        return nil, err
    }

    eventsQuery := `
    CREATE TABLE IF NOT EXISTS events (
        uid TEXT PRIMARY KEY,
        calendar_uid TEXT NOT NULL,
        title TEXT NOT NULL,
        description TEXT,
        location TEXT,
        start_utc TEXT NOT NULL,
        end_utc TEXT NOT NULL,
        is_all_day INTEGER NOT NULL DEFAULT 0,
        tzid TEXT NOT NULL,
        recurrence_rule TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        FOREIGN KEY(calendar_uid) REFERENCES calendars(uid)
    );`
    if _, err := db.Exec(eventsQuery); err != nil {
        slog.Error("DB: Ошибка при создании таблицы 'events'", "error", err)
        return nil, err
    }

    overridesQuery := `
    CREATE TABLE IF NOT EXISTS event_overrides (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        parent_uid TEXT NOT NULL,
        recurrence_id TEXT NOT NULL,
        title TEXT,
        description TEXT,
        location TEXT,
        start_utc TEXT,
        end_utc TEXT,
        is_all_day INTEGER,
        tzid TEXT,
        deleted_at TEXT,
        FOREIGN KEY(parent_uid) REFERENCES events(uid)
    );`
    if _, err := db.Exec(overridesQuery); err != nil {
        slog.Error("DB: Ошибка при создании таблицы 'event_overrides'", "error", err)
        return nil, err
    }

    exdatesQuery := `
    CREATE TABLE IF NOT EXISTS event_exdates (
        parent_uid TEXT NOT NULL,
        exdate TEXT NOT NULL,
        PRIMARY KEY(parent_uid, exdate),
        FOREIGN KEY(parent_uid) REFERENCES events(uid)
    );`
    if _, err := db.Exec(exdatesQuery); err != nil {
        slog.Error("DB: Ошибка при создании таблицы 'event_exdates'", "error", err)
        return nil, err
    }

    // Индексы для производительности календаря
    if _, err := db.Exec(`CREATE INDEX IF NOT EXISTS idx_events_calendar_start ON events(calendar_uid, start_utc)`); err != nil {
        slog.Warn("DB: Не удалось создать индекс idx_events_calendar_start", "error", err)
    }
    if _, err := db.Exec(`CREATE INDEX IF NOT EXISTS idx_events_updated_at ON events(updated_at)`); err != nil {
        slog.Warn("DB: Не удалось создать индекс idx_events_updated_at", "error", err)
    }
    if _, err := db.Exec(`CREATE INDEX IF NOT EXISTS idx_overrides_parent_rid ON event_overrides(parent_uid, recurrence_id)`); err != nil {
        slog.Warn("DB: Не удалось создать индекс idx_overrides_parent_rid", "error", err)
    }
    if _, err := db.Exec(`CREATE INDEX IF NOT EXISTS idx_exdates_parent ON event_exdates(parent_uid, exdate)`); err != nil {
        slog.Warn("DB: Не удалось создать индекс idx_exdates_parent", "error", err)
    }

    // --- Доски (Kanban/Scrum) ---
    boardsQuery := `
    CREATE TABLE IF NOT EXISTS boards (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        type TEXT NOT NULL, -- 'kanban' | 'scrum'
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
    );`
    if _, err := db.Exec(boardsQuery); err != nil {
        slog.Error("DB: Ошибка при создании таблицы 'boards'", "error", err)
        return nil, err
    }
    columnsQuery := `
    CREATE TABLE IF NOT EXISTS board_columns (
        id TEXT PRIMARY KEY,
        board_id TEXT NOT NULL,
        name TEXT NOT NULL,
        wip_limit INTEGER,
        position INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY(board_id) REFERENCES boards(id)
    );`
    if _, err := db.Exec(columnsQuery); err != nil {
        slog.Error("DB: Ошибка при создании таблицы 'board_columns'", "error", err)
        return nil, err
    }
    issuesQuery := `
    CREATE TABLE IF NOT EXISTS issues (
        id TEXT PRIMARY KEY,
        board_id TEXT NOT NULL,
        column_id TEXT NOT NULL,
        type TEXT NOT NULL, -- epic|story|task|bug|subtask
        summary TEXT NOT NULL,
        description TEXT,
        priority TEXT,
        labels TEXT, -- csv labels
        due_date TEXT, -- RFC3339
        created_by_name TEXT,
        assigned_to_name TEXT,
        responsible_name TEXT,
        note_id TEXT, -- optional link to notes.id
        position INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY(board_id) REFERENCES boards(id),
        FOREIGN KEY(column_id) REFERENCES board_columns(id)
    );`
    if _, err := db.Exec(issuesQuery); err != nil {
        slog.Error("DB: Ошибка при создании таблицы 'issues'", "error", err)
        return nil, err
    }
    // Миграции для новых колонок в issues (idempotent): добавляем, если их нет
    // created_by_name
    if _, err := db.Exec(`ALTER TABLE issues ADD COLUMN created_by_name TEXT`); err != nil {
        if !strings.Contains(err.Error(), "duplicate column name") { slog.Warn("DB: ALTER issues add created_by_name", "error", err) }
    }
    if _, err := db.Exec(`ALTER TABLE issues ADD COLUMN assigned_to_name TEXT`); err != nil {
        if !strings.Contains(err.Error(), "duplicate column name") { slog.Warn("DB: ALTER issues add assigned_to_name", "error", err) }
    }
    if _, err := db.Exec(`ALTER TABLE issues ADD COLUMN responsible_name TEXT`); err != nil {
        if !strings.Contains(err.Error(), "duplicate column name") { slog.Warn("DB: ALTER issues add responsible_name", "error", err) }
    }
    commentsQuery := `
    CREATE TABLE IF NOT EXISTS issue_comments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        issue_id TEXT NOT NULL,
        author TEXT,
        body TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY(issue_id) REFERENCES issues(id)
    );`
    if _, err := db.Exec(commentsQuery); err != nil {
        slog.Error("DB: Ошибка при создании таблицы 'issue_comments'", "error", err)
        return nil, err
    }
    sprintsQuery := `
    CREATE TABLE IF NOT EXISTS sprints (
        id TEXT PRIMARY KEY,
        board_id TEXT NOT NULL,
        name TEXT NOT NULL,
        state TEXT NOT NULL, -- planned|active|closed
        start_date TEXT,
        end_date TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY(board_id) REFERENCES boards(id)
    );`
    if _, err := db.Exec(sprintsQuery); err != nil {
        slog.Error("DB: Ошибка при создании таблицы 'sprints'", "error", err)
        return nil, err
    }
    if _, err := db.Exec(`CREATE INDEX IF NOT EXISTS idx_issues_board_column ON issues(board_id, column_id)`); err != nil {
        slog.Warn("DB: Не удалось создать индекс idx_issues_board_column", "error", err)
    }
    if _, err := db.Exec(`CREATE INDEX IF NOT EXISTS idx_issues_due ON issues(due_date)`); err != nil {
        slog.Warn("DB: Не удалось создать индекс idx_issues_due", "error", err)
    }

    // Справочники имён по ролям
    peopleQuery := `
    CREATE TABLE IF NOT EXISTS board_people (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        board_id TEXT NOT NULL,
        role TEXT NOT NULL, -- SETTER|ASSIGNEE|RESPONSIBLE
        name TEXT NOT NULL,
        UNIQUE(board_id, role, name),
        FOREIGN KEY(board_id) REFERENCES boards(id)
    );`
    if _, err := db.Exec(peopleQuery); err != nil {
        slog.Error("DB: Ошибка при создании таблицы 'board_people'", "error", err)
        return nil, err
    }

    // Кастомные поля доски и значения задач
    fieldsQuery := `
    CREATE TABLE IF NOT EXISTS board_fields (
        id TEXT PRIMARY KEY,
        board_id TEXT NOT NULL,
        name TEXT NOT NULL,
        ftype TEXT NOT NULL, -- text|number|date|enum|user
        options_json TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY(board_id) REFERENCES boards(id)
    );`
    if _, err := db.Exec(fieldsQuery); err != nil {
        slog.Error("DB: Ошибка при создании таблицы 'board_fields'", "error", err)
        return nil, err
    }
    valuesQuery := `
    CREATE TABLE IF NOT EXISTS issue_field_values (
        issue_id TEXT NOT NULL,
        field_id TEXT NOT NULL,
        value_json TEXT,
        PRIMARY KEY(issue_id, field_id),
        FOREIGN KEY(issue_id) REFERENCES issues(id) ON DELETE CASCADE,
        FOREIGN KEY(field_id) REFERENCES board_fields(id) ON DELETE CASCADE
    );`
    if _, err := db.Exec(valuesQuery); err != nil {
        slog.Error("DB: Ошибка при создании таблицы 'issue_field_values'", "error", err)
        return nil, err
    }

    // Настройки уведомлений доски
    notifQuery := `
    CREATE TABLE IF NOT EXISTS board_notifications (
        board_id TEXT PRIMARY KEY,
        due_soon_hours INTEGER NOT NULL DEFAULT 24,
        create_calendar_event INTEGER NOT NULL DEFAULT 1,
        create_default_reminders INTEGER NOT NULL DEFAULT 0,
        reminder_offsets_csv TEXT, -- запятая-разделённые минуты до события
        FOREIGN KEY(board_id) REFERENCES boards(id)
    );`
    if _, err := db.Exec(notifQuery); err != nil {
        slog.Error("DB: Ошибка при создании таблицы 'board_notifications'", "error", err)
        return nil, err
    }

    // Приоритеты доски
    prioritiesQuery := `
    CREATE TABLE IF NOT EXISTS board_priorities (
        board_id TEXT NOT NULL,
        pkey TEXT NOT NULL,
        label TEXT NOT NULL,
        color_hex TEXT NOT NULL,
        position INTEGER NOT NULL,
        PRIMARY KEY(board_id, pkey),
        FOREIGN KEY(board_id) REFERENCES boards(id)
    );`
    if _, err := db.Exec(prioritiesQuery); err != nil {
        slog.Error("DB: Ошибка при создании таблицы 'board_priorities'", "error", err)
        return nil, err
    }

    // Дополнительные таблицы для модуля «Доски»: чек-лист, теги, activity log
    checklistQuery := `
    CREATE TABLE IF NOT EXISTS issue_checklist_items (
        id TEXT PRIMARY KEY,
        issue_id TEXT NOT NULL,
        text TEXT NOT NULL,
        is_done INTEGER NOT NULL DEFAULT 0,
        order_index INTEGER NOT NULL,
        FOREIGN KEY(issue_id) REFERENCES issues(id) ON DELETE CASCADE
    );`
    if _, err := db.Exec(checklistQuery); err != nil {
        slog.Error("DB: Ошибка при создании таблицы 'issue_checklist_items'", "error", err)
        return nil, err
    }
    tagsQuery := `
    CREATE TABLE IF NOT EXISTS issue_tags (
        issue_id TEXT NOT NULL,
        tag TEXT NOT NULL,
        PRIMARY KEY (issue_id, tag),
        FOREIGN KEY(issue_id) REFERENCES issues(id) ON DELETE CASCADE
    );`
    if _, err := db.Exec(tagsQuery); err != nil {
        slog.Error("DB: Ошибка при создании таблицы 'issue_tags'", "error", err)
        return nil, err
    }
    activityQuery := `
    CREATE TABLE IF NOT EXISTS activity_log (
        id TEXT PRIMARY KEY,
        ts TEXT NOT NULL,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        action TEXT NOT NULL,
        before_json TEXT,
        after_json TEXT
    );`
    if _, err := db.Exec(activityQuery); err != nil {
        slog.Error("DB: Ошибка при создании таблицы 'activity_log'", "error", err)
        return nil, err
    }
    slog.Info("DB: Инициализация базы данных завершена успешно.")
    return db, nil
}

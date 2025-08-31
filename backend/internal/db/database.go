package db

import (
	"database/sql"
	"fmt"
	"log/slog"

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
    slog.Info("DB: Инициализация базы данных завершена успешно.")
    return db, nil
}

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
	slog.Info("DB: Инициализация базы данных завершена успешно.")
	return db, nil
}

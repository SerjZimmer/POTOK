package db

import (
	"database/sql"
	"log/slog"

	_ "github.com/mattn/go-sqlite3"
)

// InitDB инициализирует базу данных SQLite и создает/обновляет таблицы.
func InitDB(filepath string) (*sql.DB, error) {
	db, err := sql.Open("sqlite3", filepath)
	if err != nil {
		slog.Error("DB: Ошибка при открытии базы данных", "error", err)
		return nil, err
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

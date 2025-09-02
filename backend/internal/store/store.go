package store

import (
	"database/sql"
	"log/slog"
	"time" // Add time import

	"potok/backend/internal/models"

	"github.com/google/uuid"
)

// Store предоставляет методы для взаимодействия с хранилищем данных (базой данных).
type Store struct {
    db *sql.DB
}

// New создает новый экземпляр Store.
func New(db *sql.DB) *Store {
    return &Store{db: db}
}

// DB возвращает внутреннее подключение к БД для других подсистем (например, календаря).
func (s *Store) DB() *sql.DB { return s.db }

// --- Методы для Папок ---

func (s *Store) CreateFolder(name string) (*models.Folder, error) {
	id := uuid.New().String()
	folder := &models.Folder{
		ID:   id,
		Name: name,
	}
	query := `INSERT INTO folders (id, name) VALUES (?, ?)`
	_, err := s.db.Exec(query, folder.ID, folder.Name)
	if err != nil {
		slog.Error("Store: Ошибка при создании папки", "name", name, "error", err)
		return nil, err
	}
	slog.Info("Store: Папка успешно создана", "name", name, "id", id)
	return folder, nil
}

func (s *Store) GetFolders() ([]*models.Folder, error) {
	query := `SELECT id, name FROM folders`
	rows, err := s.db.Query(query)
	if err != nil {
		slog.Error("Store: Ошибка при получении списка папок", "error", err)
		return nil, err
	}
	defer rows.Close()

	var folders []*models.Folder = []*models.Folder{}
	for rows.Next() {
		var folder models.Folder
		if err := rows.Scan(&folder.ID, &folder.Name); err != nil {
			slog.Error("Store: Ошибка при сканировании строки папки", "error", err)
			return nil, err
		}
		folders = append(folders, &folder)
	}
	return folders, nil
}

func (s *Store) UpdateFolder(id, name string) (*models.Folder, error) {
	query := `UPDATE folders SET name = ? WHERE id = ?`
	_, err := s.db.Exec(query, name, id)
	if err != nil {
		slog.Error("Store: Ошибка при обновлении папки", "id", id, "error", err)
		return nil, err
	}
	slog.Info("Store: Папка успешно обновлена", "id", id, "name", name)
	return &models.Folder{ID: id, Name: name}, nil
}

func (s *Store) DeleteFolder(id string) error {
	notesQuery := `DELETE FROM notes WHERE folder_id = ?`
	_, err := s.db.Exec(notesQuery, id)
	if err != nil {
		slog.Error("Store: Ошибка при удалении заметок из папки", "id", id, "error", err)
		return err
	}

	folderQuery := `DELETE FROM folders WHERE id = ?`
	_, err = s.db.Exec(folderQuery, id)
	if err != nil {
		slog.Error("Store: Ошибка при удалении папки", "id", id, "error", err)
		return err
	}
	slog.Info("Store: Папка успешно удалена", "id", id)
	return nil
}

// --- Методы для Заметок ---

func (s *Store) CreateNote(title, content, folderID string) (*models.Note, error) {
	id := uuid.New().String()
	// Get current timestamp in RFC3339 format for SQLite DATETIME
	createdAt := time.Now().Format(time.RFC3339)
	note := &models.Note{
		ID:        id,
		Title:     title,
		Content:   content,
		FolderID:  folderID,
		CreatedAt: sql.NullString{String: createdAt, Valid: true}, // Construct sql.NullString
	}
	query := `INSERT INTO notes (id, title, content, folder_id, created_at) VALUES (?, ?, ?, ?, ?)`
	_, err := s.db.Exec(query, note.ID, note.Title, note.Content, note.FolderID, note.CreatedAt)
	if err != nil {
		slog.Error("Store: Ошибка при создании заметки", "title", title, "error", err)
		return nil, err
	}
	slog.Info("Store: Заметка успешно создана", "title", title, "id", id, "folder_id", folderID)
	return note, nil
}

func (s *Store) ListNotes(folderID string, sortBy string) ([]*models.Note, error) {
	query := `SELECT id, title, content, folder_id, created_at FROM notes WHERE folder_id = ?` // Select created_at
	switch sortBy {
	case "name":
		query += ` ORDER BY title COLLATE NOCASE ASC` // Case-insensitive sort by title ascending
	case "name_desc":
		query += ` ORDER BY title COLLATE NOCASE DESC` // Case-insensitive sort by title descending
	case "date":
		query += ` ORDER BY created_at ASC` // Sort by created_at ascending
	case "date_desc":
		query += ` ORDER BY created_at DESC` // Sort by created_at descending
	}
	rows, err := s.db.Query(query, folderID)
	if err != nil {
		slog.Error("Store: Ошибка при получении списка заметок", "folder_id", folderID, "error", err)
		return nil, err
	}
	defer rows.Close()

	var notes []*models.Note = []*models.Note{}
	for rows.Next() {
		var note models.Note
		var createdAt sql.NullString // Temporary variable for scanning
		if err := rows.Scan(&note.ID, &note.Title, &note.Content, &note.FolderID, &createdAt); err != nil { // Scan into temporary
			slog.Error("Store: Ошибка при сканировании строки заметки", "error", err)
			return nil, err
		}
		if createdAt.Valid {
			note.CreatedAt = sql.NullString{String: createdAt.String, Valid: true}
		} else {
			note.CreatedAt = sql.NullString{String: "", Valid: false} // Assign a valid but empty NullString
		}
		notes = append(notes, &note)
	}
	return notes, nil
}

func (s *Store) UpdateNote(id, title, content, folderID string) (*models.Note, error) {
	query := `UPDATE notes SET title = ?, content = ?, folder_id = ? WHERE id = ?`
	_, err := s.db.Exec(query, title, content, folderID, id)
	if err != nil {
		slog.Error("Store: Ошибка при обновлении заметки", "id", id, "error", err)
		return nil, err
	}

	note := &models.Note{
		ID:       id,
		Title:    title,
		Content:  content,
		FolderID: folderID,
	}
	slog.Info("Store: Заметка успешно обновлена", "id", id)
	return note, nil
}

func (s *Store) DeleteNote(id string) error {
	query := `DELETE FROM notes WHERE id = ?`
	_, err := s.db.Exec(query, id)
	if err != nil {
		slog.Error("Store: Ошибка при удалении заметки", "id", id, "error", err)
		return err
	}
	slog.Info("Store: Заметка успешно удалена", "id", id)
	return nil
}

func (s *Store) ListAllNotes(sortBy string) ([]*models.Note, error) {
	query := `SELECT id, title, content, folder_id, created_at FROM notes` // Select created_at
	switch sortBy {
	case "name":
		query += ` ORDER BY title COLLATE NOCASE ASC` // Case-insensitive sort by title ascending
	case "name_desc":
		query += ` ORDER BY title COLLATE NOCASE DESC` // Case-insensitive sort by title descending
	case "date":
		query += ` ORDER BY created_at ASC` // Sort by created_at ascending
	case "date_desc":
		query += ` ORDER BY created_at DESC` // Sort by created_at descending
	}
	rows, err := s.db.Query(query)
	if err != nil {
		slog.Error("Store: Ошибка при получении всех заметок", "error", err)
		return nil, err
	}
	defer rows.Close()

	var notes []*models.Note = []*models.Note{}
	for rows.Next() {
		var note models.Note
		var createdAt sql.NullString // Temporary variable for scanning
		if err := rows.Scan(&note.ID, &note.Title, &note.Content, &note.FolderID, &createdAt); err != nil { // Scan into temporary
			slog.Error("Store: Ошибка при сканировании строки заметки (ListAllNotes)", "error", err)
			return nil, err
		}
		if createdAt.Valid {
			note.CreatedAt = sql.NullString{String: createdAt.String, Valid: true}
		} else {
			note.CreatedAt = sql.NullString{String: "", Valid: false} // Assign a valid but empty NullString
		}
		notes = append(notes, &note)
	}
	return notes, nil
}

func (s *Store) DeleteFolderWithNotes(folderID string) error {
	tx, err := s.db.Begin()
	if err != nil {
		slog.Error("Store: Ошибка при начале транзакции для удаления папки с заметками", "error", err)
		return err
	}
	defer tx.Rollback() // Rollback on error

	// Delete notes in the folder
	notesQuery := `DELETE FROM notes WHERE folder_id = ?`
	_, err = tx.Exec(notesQuery, folderID)
	if err != nil {
		slog.Error("Store: Ошибка при удалении заметок в папке", "folder_id", folderID, "error", err)
		return err
	}

	// Delete the folder
	folderQuery := `DELETE FROM folders WHERE id = ?`
	_, err = tx.Exec(folderQuery, folderID)
	if err != nil {
		slog.Error("Store: Ошибка при удалении папки", "folder_id", folderID, "error", err)
		return err
	}

	slog.Info("Store: Папка и связанные заметки успешно удалены", "folder_id", folderID)
	return tx.Commit() // Commit on success
}

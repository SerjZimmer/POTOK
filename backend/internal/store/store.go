package store

import (
	"database/sql"

	"github.com/google/uuid"
	"potok/backend/internal/models"
)

// Store предоставляет методы для взаимодействия с хранилищем данных (базой данных).
type Store struct {
	db *sql.DB
}

// New создает новый экземпляр Store.
func New(db *sql.DB) *Store {
	return &Store{db: db}
}

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
		return nil, err
	}
	return folder, nil
}

func (s *Store) GetFolders() ([]*models.Folder, error) {
	query := `SELECT id, name FROM folders`
	rows, err := s.db.Query(query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var folders []*models.Folder = []*models.Folder{}
	for rows.Next() {
		var folder models.Folder
		if err := rows.Scan(&folder.ID, &folder.Name); err != nil {
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
		return nil, err
	}
	return &models.Folder{ID: id, Name: name}, nil
}

func (s *Store) DeleteFolder(id string) error {
	notesQuery := `DELETE FROM notes WHERE folder_id = ?`
	_, err := s.db.Exec(notesQuery, id)
	if err != nil {
		return err
	}

	folderQuery := `DELETE FROM folders WHERE id = ?`
	_, err = s.db.Exec(folderQuery, id)
	return err
}

// --- Методы для Заметок ---

func (s *Store) CreateNote(title, content, folderID string) (*models.Note, error) {
	id := uuid.New().String()
	note := &models.Note{
		ID:       id,
		Title:    title,
		Content:  content,
		FolderID: folderID,
	}
	query := `INSERT INTO notes (id, title, content, folder_id) VALUES (?, ?, ?, ?)`
	_, err := s.db.Exec(query, note.ID, note.Title, note.Content, note.FolderID)
	if err != nil {
		return nil, err
	}
	return note, nil
}

func (s *Store) ListNotes(folderID string) ([]*models.Note, error) {
	query := `SELECT id, title, content, folder_id FROM notes WHERE folder_id = ?`
	rows, err := s.db.Query(query, folderID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var notes []*models.Note = []*models.Note{}
	for rows.Next() {
		var note models.Note
		if err := rows.Scan(&note.ID, &note.Title, &note.Content, &note.FolderID); err != nil {
			return nil, err
		}
		notes = append(notes, &note)
	}
	return notes, nil
}

func (s *Store) UpdateNote(id, title, content, folderID string) (*models.Note, error) {
	query := `UPDATE notes SET title = ?, content = ?, folder_id = ? WHERE id = ?`
	_, err := s.db.Exec(query, title, content, folderID, id)
	if err != nil {
		return nil, err
	}

	note := &models.Note{
		ID:       id,
		Title:    title,
		Content:  content,
		FolderID: folderID,
	}
	return note, nil
}

func (s *Store) DeleteNote(id string) error {
	query := `DELETE FROM notes WHERE id = ?`
	_, err := s.db.Exec(query, id)
	return err
}

func (s *Store) ListAllNotes() ([]*models.Note, error) {
	query := `SELECT id, title, content, folder_id FROM notes`
	rows, err := s.db.Query(query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var notes []*models.Note = []*models.Note{}
	for rows.Next() {
		var note models.Note
		if err := rows.Scan(&note.ID, &note.Title, &note.Content, &note.FolderID); err != nil {
			return nil, err
		}
		notes = append(notes, &note)
	}
	return notes, nil
}

func (s *Store) DeleteFolderWithNotes(folderID string) error {
	tx, err := s.db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback() // Rollback on error

	// Delete notes in the folder
	notesQuery := `DELETE FROM notes WHERE folder_id = ?`
	_, err = tx.Exec(notesQuery, folderID)
	if err != nil {
		return err
	}

	// Delete the folder
	folderQuery := `DELETE FROM folders WHERE id = ?`
	_, err = tx.Exec(folderQuery, folderID)
	if err != nil {
		return err
	}

	return tx.Commit() // Commit on success
}
package store

import (
	"errors"
	"testing"
	"time"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/stretchr/testify/assert"
)

func TestStore_CreateFolder(t *testing.T) {
	db, mock, err := sqlmock.New(sqlmock.QueryMatcherOption(sqlmock.QueryMatcherEqual))
	if err != nil {
		t.Fatalf("an error '%s' was not expected when opening a stub database connection", err)
	}
	defer db.Close()

	s := New(db)

	tests := []struct {
		name       string
		folderName string
		mock       func()
		wantErr    bool
	}{
		{
			name:       "Success",
			folderName: "Test Folder",
			mock: func() {
				mock.ExpectExec(`INSERT INTO folders (id, name) VALUES (?, ?)`).
					WithArgs(sqlmock.AnyArg(), "Test Folder").
					WillReturnResult(sqlmock.NewResult(1, 1))
			},
			wantErr: false,
		},
		{
			name:       "Failure",
			folderName: "Test Folder",
			mock: func() {
				mock.ExpectExec(`INSERT INTO folders (id, name) VALUES (?, ?)`).
					WithArgs(sqlmock.AnyArg(), "Test Folder").
					WillReturnError(errors.New("db error"))
			},
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.mock()
			_, err := s.CreateFolder(tt.folderName)
			if tt.wantErr {
				assert.Error(t, err)
			} else {
				assert.NoError(t, err)
			}
			if err := mock.ExpectationsWereMet(); err != nil {
				t.Errorf("there were unfulfilled expectations: %s", err)
			}
		})
	}
}

func TestStore_GetFolders(t *testing.T) {
	db, mock, err := sqlmock.New(sqlmock.QueryMatcherOption(sqlmock.QueryMatcherEqual))
	if err != nil {
		t.Fatalf("an error '%s' was not expected when opening a stub database connection", err)
	}
	defer db.Close()

	s := New(db)

	tests := []struct {
		name    string
		mock    func()
		wantErr bool
	}{
		{
			name: "Success",
			mock: func() {
				rows := sqlmock.NewRows([]string{"id", "name"}).
					AddRow("1", "Folder 1").
					AddRow("2", "Folder 2")
				mock.ExpectQuery(`SELECT id, name FROM folders`).WillReturnRows(rows)
			},
			wantErr: false,
		},
		{
			name: "Failure on query",
			mock: func() {
				mock.ExpectQuery(`SELECT id, name FROM folders`).WillReturnError(errors.New("db error"))
			},
			wantErr: true,
		},
		{
			name: "Failure on scan",
			mock: func() {
				rows := sqlmock.NewRows([]string{"id", "name"}).
					AddRow("1", "Folder 1").
					AddRow("2", nil) // This will cause a scan error
				mock.ExpectQuery(`SELECT id, name FROM folders`).WillReturnRows(rows)
			},
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.mock()
			folders, err := s.GetFolders()
			if tt.wantErr {
				assert.Error(t, err)
				assert.Nil(t, folders)
			} else {
				assert.NoError(t, err)
				assert.NotNil(t, folders)
				assert.Len(t, folders, 2)
			}
			if err := mock.ExpectationsWereMet(); err != nil {
				t.Errorf("there were unfulfilled expectations: %s", err)
			}
		})
	}
}

func TestStore_UpdateFolder(t *testing.T) {
	db, mock, err := sqlmock.New(sqlmock.QueryMatcherOption(sqlmock.QueryMatcherEqual))
	if err != nil {
		t.Fatalf("an error '%s' was not expected when opening a stub database connection", err)
	}
	defer db.Close()

	s := New(db)

	tests := []struct {
		name    string
		id      string
		newName string
		mock    func()
		wantErr bool
	}{
		{
			name:    "Success",
			id:      "1",
			newName: "New Name",
			mock: func() {
				mock.ExpectExec(`UPDATE folders SET name = ? WHERE id = ?`).
					WithArgs("New Name", "1").
					WillReturnResult(sqlmock.NewResult(1, 1))
			},
			wantErr: false,
		},
		{
			name:    "Failure",
			id:      "1",
			newName: "New Name",
			mock: func() {
				mock.ExpectExec(`UPDATE folders SET name = ? WHERE id = ?`).
					WithArgs("New Name", "1").
					WillReturnError(errors.New("db error"))
			},
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.mock()
			_, err := s.UpdateFolder(tt.id, tt.newName)
			if tt.wantErr {
				assert.Error(t, err)
			} else {
				assert.NoError(t, err)
			}
			if err := mock.ExpectationsWereMet(); err != nil {
				t.Errorf("there were unfulfilled expectations: %s", err)
			}
		})
	}
}

func TestStore_DeleteFolder(t *testing.T) {
	db, mock, err := sqlmock.New(sqlmock.QueryMatcherOption(sqlmock.QueryMatcherEqual))
	if err != nil {
		t.Fatalf("an error '%s' was not expected when opening a stub database connection", err)
	}
	defer db.Close()

	s := New(db)

	tests := []struct {
		name    string
		id      string
		mock    func()
		wantErr bool
	}{
		{
			name: "Success",
			id:   "1",
			mock: func() {
				mock.ExpectExec(`DELETE FROM notes WHERE folder_id = ?`).
					WithArgs("1").
					WillReturnResult(sqlmock.NewResult(1, 1))
				mock.ExpectExec(`DELETE FROM folders WHERE id = ?`).
					WithArgs("1").
					WillReturnResult(sqlmock.NewResult(1, 1))
			},
			wantErr: false,
		},
		{
			name: "Failure on notes deletion",
			id:   "1",
			mock: func() {
				mock.ExpectExec(`DELETE FROM notes WHERE folder_id = ?`).
					WithArgs("1").
					WillReturnError(errors.New("db error"))
			},
			wantErr: true,
		},
		{
			name: "Failure on folder deletion",
			id:   "1",
			mock: func() {
				mock.ExpectExec(`DELETE FROM notes WHERE folder_id = ?`).
					WithArgs("1").
					WillReturnResult(sqlmock.NewResult(1, 1))
				mock.ExpectExec(`DELETE FROM folders WHERE id = ?`).
					WithArgs("1").
					WillReturnError(errors.New("db error"))
			},
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.mock()
			err := s.DeleteFolder(tt.id)
			if tt.wantErr {
				assert.Error(t, err)
			} else {
				assert.NoError(t, err)
			}
			if err := mock.ExpectationsWereMet(); err != nil {
				t.Errorf("there were unfulfilled expectations: %s", err)
			}
		})
	}
}

func TestStore_CreateNote(t *testing.T) {
	db, mock, err := sqlmock.New(sqlmock.QueryMatcherOption(sqlmock.QueryMatcherEqual))
	if err != nil {
		t.Fatalf("an error '%s' was not expected when opening a stub database connection", err)
	}
	defer db.Close()

	s := New(db)

	tests := []struct {
		name     string
		title    string
		content  string
		folderID string
		mock     func()
		wantErr  bool
	}{
		{
			name:     "Success",
			title:    "Test Note",
			content:  "Test Content",
			folderID: "1",
			mock: func() {
				mock.ExpectExec(`INSERT INTO notes (id, title, content, folder_id, created_at) VALUES (?, ?, ?, ?, ?)`).
					WithArgs(sqlmock.AnyArg(), "Test Note", "Test Content", "1", sqlmock.AnyArg()).
					WillReturnResult(sqlmock.NewResult(1, 1))
			},
			wantErr: false,
		},
		{
			name:     "Failure",
			title:    "Test Note",
			content:  "Test Content",
			folderID: "1",
			mock: func() {
				mock.ExpectExec(`INSERT INTO notes (id, title, content, folder_id, created_at) VALUES (?, ?, ?, ?, ?)`).
					WithArgs(sqlmock.AnyArg(), "Test Note", "Test Content", "1", sqlmock.AnyArg()).
					WillReturnError(errors.New("db error"))
			},
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.mock()
			_, err := s.CreateNote(tt.title, tt.content, tt.folderID)
			if tt.wantErr {
				assert.Error(t, err)
			} else {
				assert.NoError(t, err)
			}
			if err := mock.ExpectationsWereMet(); err != nil {
				t.Errorf("there were unfulfilled expectations: %s", err)
			}
		})
	}
}

func TestStore_ListNotes(t *testing.T) {
	db, mock, err := sqlmock.New(sqlmock.QueryMatcherOption(sqlmock.QueryMatcherEqual))
	if err != nil {
		t.Fatalf("an error '%s' was not expected when opening a stub database connection", err)
	}
	defer db.Close()

	s := New(db)

	tests := []struct {
		name     string
		folderID string
		sortBy   string
		mock     func()
		wantErr  bool
	}{
		{
			name:     "Success with nil created_at",
			folderID: "1",
			sortBy:   "date_desc",
			mock: func() {
				rows := sqlmock.NewRows([]string{"id", "title", "content", "folder_id", "created_at"}).
					AddRow("1", "Note 1", "Content 1", "1", time.Now().Format(time.RFC3339)).
					AddRow("2", "Note 2", "Content 2", "1", nil)
				mock.ExpectQuery(`SELECT id, title, content, folder_id, created_at FROM notes WHERE folder_id = ? ORDER BY created_at DESC`).
					WithArgs("1").
					WillReturnRows(rows)
			},
			wantErr: false,
		},
		{
			name:     "Failure on query",
			folderID: "1",
			sortBy:   "date_desc",
			mock: func() {
				mock.ExpectQuery(`SELECT id, title, content, folder_id, created_at FROM notes WHERE folder_id = ? ORDER BY created_at DESC`).
					WithArgs("1").
					WillReturnError(errors.New("db error"))
			},
			wantErr: true,
		},
		{
			name:     "Failure on scan",
			folderID: "1",
			sortBy:   "date_desc",
			mock: func() {
				rows := sqlmock.NewRows([]string{"id", "title", "content", "folder_id", "created_at"}).
					AddRow("1", "Note 1", "Content 1", "1", time.Now().Format(time.RFC3339)).
					AddRow("2", nil, "Content 2", "1", time.Now().Format(time.RFC3339)) // This will cause a scan error
				mock.ExpectQuery(`SELECT id, title, content, folder_id, created_at FROM notes WHERE folder_id = ? ORDER BY created_at DESC`).
					WithArgs("1").
					WillReturnRows(rows)
			},
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.mock()
			notes, err := s.ListNotes(tt.folderID, tt.sortBy)
			if tt.wantErr {
				assert.Error(t, err)
				assert.Nil(t, notes)
			} else {
				assert.NoError(t, err)
				assert.NotNil(t, notes)
				assert.Len(t, notes, 2)
			}
			if err := mock.ExpectationsWereMet(); err != nil {
				t.Errorf("there were unfulfilled expectations: %s", err)
			}
		})
	}
}

func TestStore_UpdateNote(t *testing.T) {
	db, mock, err := sqlmock.New(sqlmock.QueryMatcherOption(sqlmock.QueryMatcherEqual))
	if err != nil {
		t.Fatalf("an error '%s' was not expected when opening a stub database connection", err)
	}
	defer db.Close()

	s := New(db)

	tests := []struct {
		name     string
		id       string
		title    string
		content  string
		folderID string
		mock     func()
		wantErr  bool
	}{
		{
			name:     "Success",
			id:       "1",
			title:    "New Title",
			content:  "New Content",
			folderID: "1",
			mock: func() {
				mock.ExpectExec(`UPDATE notes SET title = ?, content = ?, folder_id = ? WHERE id = ?`).
					WithArgs("New Title", "New Content", "1", "1").
					WillReturnResult(sqlmock.NewResult(1, 1))
			},
			wantErr: false,
		},
		{
			name:     "Failure",
			id:       "1",
			title:    "New Title",
			content:  "New Content",
			folderID: "1",
			mock: func() {
				mock.ExpectExec(`UPDATE notes SET title = ?, content = ?, folder_id = ? WHERE id = ?`).
					WithArgs("New Title", "New Content", "1", "1").
					WillReturnError(errors.New("db error"))
			},
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.mock()
			_, err := s.UpdateNote(tt.id, tt.title, tt.content, tt.folderID)
			if tt.wantErr {
				assert.Error(t, err)
			} else {
				assert.NoError(t, err)
			}
			if err := mock.ExpectationsWereMet(); err != nil {
				t.Errorf("there were unfulfilled expectations: %s", err)
			}
		})
	}
}

func TestStore_DeleteNote(t *testing.T) {
	db, mock, err := sqlmock.New(sqlmock.QueryMatcherOption(sqlmock.QueryMatcherEqual))
	if err != nil {
		t.Fatalf("an error '%s' was not expected when opening a stub database connection", err)
	}
	defer db.Close()

	s := New(db)

	tests := []struct {
		name    string
		id      string
		mock    func()
		wantErr bool
	}{
		{
			name: "Success",
			id:   "1",
			mock: func() {
				mock.ExpectExec(`DELETE FROM notes WHERE id = ?`).
					WithArgs("1").
					WillReturnResult(sqlmock.NewResult(1, 1))
			},
			wantErr: false,
		},
		{
			name: "Failure",
			id:   "1",
			mock: func() {
				mock.ExpectExec(`DELETE FROM notes WHERE id = ?`).
					WithArgs("1").
					WillReturnError(errors.New("db error"))
			},
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.mock()
			err := s.DeleteNote(tt.id)
			if tt.wantErr {
				assert.Error(t, err)
			} else {
				assert.NoError(t, err)
			}
			if err := mock.ExpectationsWereMet(); err != nil {
				t.Errorf("there were unfulfilled expectations: %s", err)
			}
		})
	}
}

func TestStore_ListAllNotes(t *testing.T) {
	db, mock, err := sqlmock.New(sqlmock.QueryMatcherOption(sqlmock.QueryMatcherEqual))
	if err != nil {
		t.Fatalf("an error '%s' was not expected when opening a stub database connection", err)
	}
	defer db.Close()

	s := New(db)

	tests := []struct {
		name    string
		sortBy  string
		mock    func()
		wantErr bool
	}{
		{
			name:   "Success with nil created_at",
			sortBy: "date_desc",
			mock: func() {
				rows := sqlmock.NewRows([]string{"id", "title", "content", "folder_id", "created_at"}).
					AddRow("1", "Note 1", "Content 1", "1", time.Now().Format(time.RFC3339)).
					AddRow("2", "Note 2", "Content 2", "2", nil)
				mock.ExpectQuery(`SELECT id, title, content, folder_id, created_at FROM notes ORDER BY created_at DESC`).
					WillReturnRows(rows)
			},
			wantErr: false,
		},
		{
			name:   "Failure on query",
			sortBy: "date_desc",
			mock: func() {
				mock.ExpectQuery(`SELECT id, title, content, folder_id, created_at FROM notes ORDER BY created_at DESC`).
					WillReturnError(errors.New("db error"))
			},
			wantErr: true,
		},
		{
			name:   "Failure on scan",
			sortBy: "date_desc",
			mock: func() {
				rows := sqlmock.NewRows([]string{"id", "title", "content", "folder_id", "created_at"}).
					AddRow("1", "Note 1", "Content 1", "1", time.Now().Format(time.RFC3339)).
					AddRow("2", nil, "Content 2", "2", time.Now().Format(time.RFC3339)) // This will cause a scan error
				mock.ExpectQuery(`SELECT id, title, content, folder_id, created_at FROM notes ORDER BY created_at DESC`).
					WillReturnRows(rows)
			},
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.mock()
			notes, err := s.ListAllNotes(tt.sortBy)
			if tt.wantErr {
				assert.Error(t, err)
				assert.Nil(t, notes)
			} else {
				assert.NoError(t, err)
				assert.NotNil(t, notes)
				assert.Len(t, notes, 2)
			}
			if err := mock.ExpectationsWereMet(); err != nil {
				t.Errorf("there were unfulfilled expectations: %s", err)
			}
		})
	}
}

func TestStore_DeleteFolderWithNotes(t *testing.T) {
	db, mock, err := sqlmock.New(sqlmock.QueryMatcherOption(sqlmock.QueryMatcherEqual))
	if err != nil {
		t.Fatalf("an error '%s' was not expected when opening a stub database connection", err)
	}
	defer db.Close()

	s := New(db)

	tests := []struct {
		name     string
		folderID string
		mock     func()
		wantErr  bool
	}{
		{
			name:     "Success",
			folderID: "1",
			mock: func() {
				mock.ExpectBegin()
				mock.ExpectExec(`DELETE FROM notes WHERE folder_id = ?`).
					WithArgs("1").
					WillReturnResult(sqlmock.NewResult(1, 1))
				mock.ExpectExec(`DELETE FROM folders WHERE id = ?`).
					WithArgs("1").
					WillReturnResult(sqlmock.NewResult(1, 1))
				mock.ExpectCommit()
			},
			wantErr: false,
		},
		{
			name:     "Failure on begin",
			folderID: "1",
			mock: func() {
				mock.ExpectBegin().WillReturnError(errors.New("db error"))
			},
			wantErr: true,
		},
		{
			name:     "Failure on notes deletion",
			folderID: "1",
			mock: func() {
				mock.ExpectBegin()
				mock.ExpectExec(`DELETE FROM notes WHERE folder_id = ?`).
					WithArgs("1").
					WillReturnError(errors.New("db error"))
				mock.ExpectRollback()
			},
			wantErr: true,
		},
		{
			name:     "Failure on folder deletion",
			folderID: "1",
			mock: func() {
				mock.ExpectBegin()
				mock.ExpectExec(`DELETE FROM notes WHERE folder_id = ?`).
					WithArgs("1").
					WillReturnResult(sqlmock.NewResult(1, 1))
				mock.ExpectExec(`DELETE FROM folders WHERE id = ?`).
					WithArgs("1").
					WillReturnError(errors.New("db error"))
				mock.ExpectRollback()
			},
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.mock()
			err := s.DeleteFolderWithNotes(tt.folderID)
			if tt.wantErr {
				assert.Error(t, err)
			} else {
				assert.NoError(t, err)
			}
			if err := mock.ExpectationsWereMet(); err != nil {
				t.Errorf("there were unfulfilled expectations: %s", err)
			}
		})
	}
}

func TestStore_DB(t *testing.T) {
	db, _, err := sqlmock.New(sqlmock.QueryMatcherOption(sqlmock.QueryMatcherEqual))
	if err != nil {
		t.Fatalf("an error '%s' was not expected when opening a stub database connection", err)
	}
	defer db.Close()

	s := New(db)
	assert.NotNil(t, s.DB())
}
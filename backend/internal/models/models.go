package models

import "database/sql" // Add database/sql import

// Folder представляет папку для заметок.
type Folder struct {
	ID   string `json:"id"`
	Name string `json:"name"`
}

// Note представляет заметку.
type Note struct {
	ID        string `json:"id"`
	Title     string `json:"title"`
	Content   string `json:"content"`
	FolderID  string `json:"folder_id"`
	CreatedAt sql.NullString `json:"created_at"` // Use sql.NullString for CreatedAt
}

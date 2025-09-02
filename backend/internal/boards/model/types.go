package model

import "time"

type Board struct {
    ID        string    `json:"id"`
    Name      string    `json:"name"`
    Type      string    `json:"type"` // kanban|scrum
    CreatedAt time.Time `json:"createdAt"`
    UpdatedAt time.Time `json:"updatedAt"`
}

type Column struct {
    ID        string    `json:"id"`
    BoardID   string    `json:"boardId"`
    Name      string    `json:"name"`
    WIPLimit  *int      `json:"wipLimit,omitempty"`
    Position  int       `json:"position"`
    CreatedAt time.Time `json:"createdAt"`
    UpdatedAt time.Time `json:"updatedAt"`
}

type Issue struct {
    ID          string    `json:"id"`
    BoardID     string    `json:"boardId"`
    ColumnID    string    `json:"columnId"`
    Type        string    `json:"type"`
    Summary     string    `json:"summary"`
    Description *string   `json:"description,omitempty"`
    Priority    *string   `json:"priority,omitempty"`
    Labels      *string   `json:"labels,omitempty"`
    DueDate     *time.Time `json:"dueDate,omitempty"`
    CreatedBy   *string   `json:"createdBy,omitempty"`
    AssignedTo  *string   `json:"assignedTo,omitempty"`
    Responsible *string   `json:"responsible,omitempty"`
    NoteID      *string   `json:"noteId,omitempty"`
    Position    int       `json:"position"`
    CreatedAt   time.Time `json:"createdAt"`
    UpdatedAt   time.Time `json:"updatedAt"`
}

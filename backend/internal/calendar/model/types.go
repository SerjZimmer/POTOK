package model

import "time"

type Calendar struct {
    UID         string     `json:"uid"`
    Name        string     `json:"name"`
    ColorHex    string     `json:"colorHex"`
    IsVisible   bool       `json:"isVisible"`
    TZIDDefault string     `json:"tzidDefault"`
    CreatedAt   time.Time  `json:"createdAt"`
    UpdatedAt   time.Time  `json:"updatedAt"`
    DeletedAt   *time.Time `json:"deletedAt,omitempty"`
    ETag        string     `json:"-"`
}

type Event struct {
    UID           string     `json:"uid"`
    CalendarUID   string     `json:"calendarUid"`
    Title         string     `json:"title"`
    Description   *string    `json:"description,omitempty"`
    Location      *string    `json:"location,omitempty"`
    StartUTC      time.Time  `json:"startUtc"`
    EndUTC        time.Time  `json:"endUtc"`
    IsAllDay      bool       `json:"isAllDay"`
    TZID          string     `json:"tzid"`
    RecurrenceRule *string   `json:"recurrenceRule,omitempty"`
    Exdates       []time.Time `json:"exdates,omitempty"`
    ParentUID     *string    `json:"parentUid,omitempty"`
    RecurrenceID  *string    `json:"recurrenceId,omitempty"`
    CreatedAt     time.Time  `json:"createdAt"`
    UpdatedAt     time.Time  `json:"updatedAt"`
    DeletedAt     *time.Time `json:"deletedAt,omitempty"`
    ETag          string     `json:"-"`
}

type Reminder struct {
    ID            int    `json:"id"`
    EventUID      string `json:"eventUid"`
    OffsetMinutes int    `json:"offsetMinutes"`
    Method        string `json:"method"`
}

type PageMeta struct {
    Limit      int     `json:"limit"`
    NextCursor *string `json:"nextCursor,omitempty"`
    Total      *int    `json:"total,omitempty"`
}

type ErrorResponse struct {
    Code    string                 `json:"code"`
    Message string                 `json:"message"`
    Details map[string]interface{} `json:"details,omitempty"`
}


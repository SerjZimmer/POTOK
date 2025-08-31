package service

import (
    "context"
    "time"
    "potok/backend/internal/calendar/model"
)

type CalendarService interface {
    List(ctx context.Context, limit int, cursor string) ([]model.Calendar, *model.PageMeta, error)
    Create(ctx context.Context, c model.Calendar) (model.Calendar, error)
    Get(ctx context.Context, uid string) (model.Calendar, bool, error)
    Patch(ctx context.Context, uid string, patch map[string]interface{}, ifMatch string) (model.Calendar, error)
    Delete(ctx context.Context, uid string) error
}

// Stub implementation (in-memory store will back this later)
type NoopCalendarService struct{}

func (s NoopCalendarService) List(ctx context.Context, limit int, cursor string) ([]model.Calendar, *model.PageMeta, error) {
    return []model.Calendar{}, &model.PageMeta{Limit: limit, NextCursor: nil, Total: nil}, nil
}
func (s NoopCalendarService) Create(ctx context.Context, c model.Calendar) (model.Calendar, error) {
    now := time.Now().UTC()
    c.CreatedAt, c.UpdatedAt = now, now
    return c, nil
}
func (s NoopCalendarService) Get(ctx context.Context, uid string) (model.Calendar, bool, error) {
    return model.Calendar{}, false, nil
}
func (s NoopCalendarService) Patch(ctx context.Context, uid string, patch map[string]interface{}, ifMatch string) (model.Calendar, error) {
    return model.Calendar{UID: uid, Name: "patched", ColorHex: "#FFC107", IsVisible: true, TZIDDefault: "UTC", CreatedAt: time.Now().UTC(), UpdatedAt: time.Now().UTC()}, nil
}
func (s NoopCalendarService) Delete(ctx context.Context, uid string) error { return nil }


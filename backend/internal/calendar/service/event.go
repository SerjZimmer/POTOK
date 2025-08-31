package service

import (
    "context"
    "time"
    "potok/backend/internal/calendar/model"
)

type EventService interface {
    List(ctx context.Context, filter map[string]interface{}) ([]model.Event, *model.PageMeta, error)
    Create(ctx context.Context, e model.Event) (model.Event, error)
    Get(ctx context.Context, uid string) (model.Event, bool, error)
    Patch(ctx context.Context, uid string, patch map[string]interface{}, ifMatch string) (model.Event, error)
    Delete(ctx context.Context, uid string) error
}

type NoopEventService struct{}

func (s NoopEventService) List(ctx context.Context, filter map[string]interface{}) ([]model.Event, *model.PageMeta, error) {
    return []model.Event{}, &model.PageMeta{Limit: 50}, nil
}
func (s NoopEventService) Create(ctx context.Context, e model.Event) (model.Event, error) {
    now := time.Now().UTC()
    e.CreatedAt, e.UpdatedAt = now, now
    return e, nil
}
func (s NoopEventService) Get(ctx context.Context, uid string) (model.Event, bool, error) {
    return model.Event{}, false, nil
}
func (s NoopEventService) Patch(ctx context.Context, uid string, patch map[string]interface{}, ifMatch string) (model.Event, error) {
    return model.Event{UID: uid, Title: "patched", StartUTC: time.Now().UTC(), EndUTC: time.Now().UTC().Add(time.Hour), TZID: "UTC", IsAllDay: false, CreatedAt: time.Now().UTC(), UpdatedAt: time.Now().UTC()}, nil
}
func (s NoopEventService) Delete(ctx context.Context, uid string) error { return nil }


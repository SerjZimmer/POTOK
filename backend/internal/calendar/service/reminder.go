package service

import (
    "context"
    "potok/backend/internal/calendar/model"
)

type ReminderService interface {
    List(ctx context.Context, eventUID string) ([]model.Reminder, error)
    Replace(ctx context.Context, eventUID string, items []model.Reminder) error
    Add(ctx context.Context, eventUID string, item model.Reminder) (model.Reminder, error)
    Delete(ctx context.Context, eventUID string, reminderID int) error
}

type NoopReminderService struct{}

func (s NoopReminderService) List(ctx context.Context, eventUID string) ([]model.Reminder, error) {
    return []model.Reminder{}, nil
}
func (s NoopReminderService) Replace(ctx context.Context, eventUID string, items []model.Reminder) error {
    return nil
}
func (s NoopReminderService) Add(ctx context.Context, eventUID string, item model.Reminder) (model.Reminder, error) {
    return item, nil
}
func (s NoopReminderService) Delete(ctx context.Context, eventUID string, reminderID int) error { return nil }


package httpapi

import (
    "net/http"
    "net/http/httptest"
    "testing"
    calsvc "potok/backend/internal/calendar/service"
)

func TestCalendarsList(t *testing.T) {
    r := NewRouterWithServices(
        calsvc.NewInMemoryCalendarService(),
        calsvc.NewInMemoryEventService(),
        calsvc.NoopReminderService{},
        calsvc.NoopSyncService{},
    )
    req := httptest.NewRequest(http.MethodGet, "/v1/calendars", nil)
    w := httptest.NewRecorder()
    r.ServeHTTP(w, req)
    if w.Code != http.StatusOK {
        t.Fatalf("expected 200, got %d", w.Code)
    }
}

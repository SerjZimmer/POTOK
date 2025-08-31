package httpapi

import (
    "net/http"
    "net/http/httptest"
    "testing"
)

func TestCalendarsList(t *testing.T) {
    r := NewRouter()
    req := httptest.NewRequest(http.MethodGet, "/v1/calendars", nil)
    w := httptest.NewRecorder()
    r.ServeHTTP(w, req)
    if w.Code != http.StatusOK {
        t.Fatalf("expected 200, got %d", w.Code)
    }
}


package httpapi

import (
    "encoding/json"
    "net/http"
    "strconv"

    "github.com/go-chi/chi/v5"
    mw "potok/backend/internal/calendar/http/middleware"
    "potok/backend/internal/calendar/model"
    "potok/backend/internal/calendar/service"
)

type Router struct {
    calendars service.CalendarService
    events    service.EventService
    reminders service.ReminderService
    sync      service.SyncService
}

func NewRouter() http.Handler {
    r := chi.NewRouter()
    r.Use(mw.RequestID, mw.Logging, mw.Auth)

    api := &Router{
        calendars: service.NoopCalendarService{},
        events:    service.NoopEventService{},
        reminders: service.NoopReminderService{},
        sync:      service.NoopSyncService{},
    }

    // Calendars
    r.Get("/v1/calendars", api.listCalendars)
    r.Post("/v1/calendars", api.createCalendar)
    r.Get("/v1/calendars/{calendarUid}", api.getCalendar)
    r.Patch("/v1/calendars/{calendarUid}", api.patchCalendar)
    r.Delete("/v1/calendars/{calendarUid}", api.deleteCalendar)

    // Events
    r.Get("/v1/events", api.listEvents)
    r.Post("/v1/events", api.createEvent)
    r.Get("/v1/events/{eventUid}", api.getEvent)
    r.Patch("/v1/events/{eventUid}", api.patchEvent)
    r.Delete("/v1/events/{eventUid}", api.deleteEvent)

    // Reminders
    r.Get("/v1/events/{eventUid}/reminders", api.listReminders)
    r.Put("/v1/events/{eventUid}/reminders", api.putReminders)
    r.Post("/v1/events/{eventUid}/reminders", api.postReminder)
    r.Delete("/v1/events/{eventUid}/reminders/{reminderId}", api.deleteReminder)

    // Sync
    r.Get("/v1/sync/delta", api.getDelta)

    // Import/Export stubs
    r.Post("/v1/import/ics", func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusAccepted) })
    r.Get("/v1/export/ics", func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusOK) })

    return r
}

// ---- Handlers (minimal stubs) ----

func (rt *Router) listCalendars(w http.ResponseWriter, r *http.Request) {
    items, meta, _ := rt.calendars.List(r.Context(), 50, "")
    respond(w, http.StatusOK, map[string]any{"items": items, "meta": meta}, "")
}

func (rt *Router) createCalendar(w http.ResponseWriter, r *http.Request) {
    var c model.Calendar
    _ = json.NewDecoder(r.Body).Decode(&c)
    created, _ := rt.calendars.Create(r.Context(), c)
    respond(w, http.StatusCreated, created, "")
}

func (rt *Router) getCalendar(w http.ResponseWriter, r *http.Request) {
    uid := chi.URLParam(r, "calendarUid")
    c, ok, _ := rt.calendars.Get(r.Context(), uid)
    if !ok { respond(w, http.StatusNotFound, model.ErrorResponse{Code: "not_found", Message: "calendar"}, ""); return }
    respond(w, http.StatusOK, c, "W/\"etag\"")
}

func (rt *Router) patchCalendar(w http.ResponseWriter, r *http.Request) {
    uid := chi.URLParam(r, "calendarUid")
    ifMatch := r.Header.Get("If-Match")
    var patch map[string]any
    _ = json.NewDecoder(r.Body).Decode(&patch)
    c, _ := rt.calendars.Patch(r.Context(), uid, patch, ifMatch)
    respond(w, http.StatusOK, c, "W/\"etag\"")
}

func (rt *Router) deleteCalendar(w http.ResponseWriter, r *http.Request) {
    uid := chi.URLParam(r, "calendarUid")
    _ = rt.calendars.Delete(r.Context(), uid)
    w.WriteHeader(http.StatusNoContent)
}

func (rt *Router) listEvents(w http.ResponseWriter, r *http.Request) {
    items, meta, _ := rt.events.List(r.Context(), map[string]any{})
    respond(w, http.StatusOK, map[string]any{"items": items, "meta": meta}, "W/\"etag\"")
}

func (rt *Router) createEvent(w http.ResponseWriter, r *http.Request) {
    var e model.Event
    _ = json.NewDecoder(r.Body).Decode(&e)
    created, _ := rt.events.Create(r.Context(), e)
    respond(w, http.StatusCreated, created, "")
}

func (rt *Router) getEvent(w http.ResponseWriter, r *http.Request) {
    uid := chi.URLParam(r, "eventUid")
    e, ok, _ := rt.events.Get(r.Context(), uid)
    if !ok { respond(w, http.StatusNotFound, model.ErrorResponse{Code: "not_found", Message: "event"}, ""); return }
    respond(w, http.StatusOK, e, "W/\"etag\"")
}

func (rt *Router) patchEvent(w http.ResponseWriter, r *http.Request) {
    uid := chi.URLParam(r, "eventUid")
    ifMatch := r.Header.Get("If-Match")
    var patch map[string]any
    _ = json.NewDecoder(r.Body).Decode(&patch)
    e, _ := rt.events.Patch(r.Context(), uid, patch, ifMatch)
    respond(w, http.StatusOK, e, "W/\"etag\"")
}

func (rt *Router) deleteEvent(w http.ResponseWriter, r *http.Request) {
    uid := chi.URLParam(r, "eventUid")
    _ = rt.events.Delete(r.Context(), uid)
    w.WriteHeader(http.StatusNoContent)
}

func (rt *Router) listReminders(w http.ResponseWriter, r *http.Request) {
    uid := chi.URLParam(r, "eventUid")
    items, _ := rt.reminders.List(r.Context(), uid)
    respond(w, http.StatusOK, items, "")
}

func (rt *Router) putReminders(w http.ResponseWriter, r *http.Request) {
    uid := chi.URLParam(r, "eventUid")
    var arr []model.Reminder
    _ = json.NewDecoder(r.Body).Decode(&arr)
    _ = rt.reminders.Replace(r.Context(), uid, arr)
    w.WriteHeader(http.StatusNoContent)
}

func (rt *Router) postReminder(w http.ResponseWriter, r *http.Request) {
    uid := chi.URLParam(r, "eventUid")
    var it model.Reminder
    _ = json.NewDecoder(r.Body).Decode(&it)
    created, _ := rt.reminders.Add(r.Context(), uid, it)
    respond(w, http.StatusCreated, created, "")
}

func (rt *Router) deleteReminder(w http.ResponseWriter, r *http.Request) {
    uid := chi.URLParam(r, "eventUid")
    idStr := chi.URLParam(r, "reminderId")
    id, _ := strconv.Atoi(idStr)
    _ = rt.reminders.Delete(r.Context(), uid, id)
    w.WriteHeader(http.StatusNoContent)
}

func (rt *Router) getDelta(w http.ResponseWriter, r *http.Request) {
    items, next, newAnchor, _ := rt.sync.Delta(r.Context(), r.URL.Query().Get("anchor"), 100, r.URL.Query().Get("cursor"))
    respond(w, http.StatusOK, map[string]any{"items": items, "nextCursor": next, "newAnchor": newAnchor}, "")
}

func respond(w http.ResponseWriter, status int, payload interface{}, etag string) {
    w.Header().Set("Content-Type", "application/json")
    if etag != "" { w.Header().Set("ETag", etag) }
    w.WriteHeader(status)
    if payload == nil { return }
    _ = json.NewEncoder(w).Encode(payload)
}


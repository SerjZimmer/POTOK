package service

import (
	"context"
	"database/sql"
	"testing"
	"time"

	_ "github.com/mattn/go-sqlite3"
	"github.com/stretchr/testify/require"
	"potok/backend/internal/calendar/model"
)

// create in-memory DB with schema
func testDB(t *testing.T) *sql.DB {
	db, err := sql.Open("sqlite3", ":memory:")
	require.NoError(t, err)
	t.Cleanup(func() {
		db.Close()
	})

	// minimal schema (копия из InitDB)
	_, err = db.Exec(`
    CREATE TABLE calendars(uid TEXT PRIMARY KEY,name TEXT,color_hex TEXT,is_visible INTEGER,tzid_default TEXT,created_at TEXT,updated_at TEXT,deleted_at TEXT);
    CREATE TABLE events(uid TEXT PRIMARY KEY,calendar_uid TEXT,title TEXT,description TEXT,location TEXT,start_utc TEXT,end_utc TEXT,is_all_day INTEGER,tzid TEXT,recurrence_rule TEXT,created_at TEXT,updated_at TEXT,deleted_at TEXT);
    CREATE TABLE event_overrides(id INTEGER PRIMARY KEY AUTOINCREMENT,parent_uid TEXT,recurrence_id TEXT,title TEXT,description TEXT,location TEXT,start_utc TEXT,end_utc TEXT,is_all_day INTEGER,tzid TEXT,deleted_at TEXT);
    CREATE TABLE event_exdates(parent_uid TEXT, exdate TEXT, PRIMARY KEY(parent_uid,exdate));`)
	require.NoError(t, err)
	return db
}

func TestCalendarService(t *testing.T) {
	db := testDB(t)
	calSvc := NewSQLiteCalendarService(db)
	ctx := context.Background()

	t.Run("Create and Get Calendar", func(t *testing.T) {
		cal := model.Calendar{
			UID:         "cal-1",
			Name:        "Личный",
			ColorHex:    "#FFC107",
			TZIDDefault: "UTC",
		}

		createdCal, err := calSvc.Create(ctx, cal)
		require.NoError(t, err)

		getCal, ok, err := calSvc.Get(ctx, cal.UID)
		require.NoError(t, err)
		require.True(t, ok)

		// Ignore time fields for comparison
		getCal.CreatedAt = createdCal.CreatedAt
		getCal.UpdatedAt = createdCal.UpdatedAt

		require.Equal(t, createdCal, getCal)
	})

	//t.Run("List Calendars", func(t *testing.T) {
	//	calSvc := NewSQLiteCalendarService(db)
	//
	//	_, err := calSvc.Create(ctx, model.Calendar{UID: "cal-1", Name: "Личный"})
	//	require.NoError(t, err)
	//	_, err = calSvc.Create(ctx, model.Calendar{UID: "cal-2", Name: "Рабочий"})
	//	require.NoError(t, err)
	//
	//	cals, _, err := calSvc.List(ctx, 10, "")
	//	require.NoError(t, err)
	//	require.Len(t, cals, 2)
	//})

	t.Run("Patch Calendar", func(t *testing.T) {
		db := testDB(t)
		calSvc := NewSQLiteCalendarService(db)

		cal, err := calSvc.Create(ctx, model.Calendar{UID: "cal-1", Name: "Личный"})
		require.NoError(t, err)

		patch := map[string]interface{}{
			"name": "Personal",
		}
		patchedCal, err := calSvc.Patch(ctx, cal.UID, patch, "")
		require.NoError(t, err)
		require.Equal(t, "Personal", patchedCal.Name)
	})

	t.Run("Delete Calendar", func(t *testing.T) {
		db := testDB(t)
		calSvc := NewSQLiteCalendarService(db)

		cal, err := calSvc.Create(ctx, model.Calendar{UID: "cal-1", Name: "Личный"})
		require.NoError(t, err)

		err = calSvc.Delete(ctx, cal.UID)
		require.NoError(t, err)

		_, ok, err := calSvc.Get(ctx, cal.UID)
		require.NoError(t, err)
		require.False(t, ok)
	})
}

func TestEventService(t *testing.T) {
	db := testDB(t)
	calSvc := NewSQLiteCalendarService(db)
	ctx := context.Background()

	cal, err := calSvc.Create(ctx, model.Calendar{UID: "cal-1", Name: "Личный"})
	require.NoError(t, err)

	t.Run("Create and Get Event", func(t *testing.T) {
		evSvc := NewSQLiteEventService(db)

		event := model.Event{
			UID:         "evt-1",
			CalendarUID: cal.UID,
			Title:       "Test Event",
			StartUTC:    time.Date(2025, 9, 1, 9, 0, 0, 0, time.UTC),
			EndUTC:      time.Date(2025, 9, 1, 10, 0, 0, 0, time.UTC),
			TZID:        "UTC",
		}

		createdEvent, err := evSvc.Create(ctx, event)
		require.NoError(t, err)

		getEvent, ok, err := evSvc.Get(ctx, event.UID)
		require.NoError(t, err)
		require.True(t, ok)

		// Ignore time fields for comparison
		getEvent.CreatedAt = createdEvent.CreatedAt
		getEvent.UpdatedAt = createdEvent.UpdatedAt

		require.Equal(t, createdEvent, getEvent)
	})

	//t.Run("List Events", func(t *testing.T) {
	//	evSvc := NewSQLiteEventService(db)
	//
	//	_, err := evSvc.Create(ctx, model.Event{UID: "evt-1", CalendarUID: cal.UID, Title: "Event 1"})
	//	require.NoError(t, err)
	//	_, err = evSvc.Create(ctx, model.Event{UID: "evt-2", CalendarUID: cal.UID, Title: "Event 2"})
	//	require.NoError(t, err)
	//
	//	events, _, err := evSvc.List(ctx, nil)
	//	require.NoError(t, err)
	//	require.Len(t, events, 2)
	//})
	//
	//t.Run("Patch Event", func(t *testing.T) {
	//	evSvc := NewSQLiteEventService(db)
	//
	//	event, err := evSvc.Create(ctx, model.Event{UID: "evt-1", CalendarUID: cal.UID, Title: "Test Event"})
	//	require.NoError(t, err)
	//
	//	patch := map[string]interface{}{
	//		"title": "Updated Event",
	//	}
	//	patchedEvent, err := evSvc.Patch(ctx, event.UID, patch, "")
	//	require.NoError(t, err)
	//	require.Equal(t, "Updated Event", patchedEvent.Title)
	//})
	//
	//t.Run("Delete Event", func(t *testing.T) {
	//	evSvc := NewSQLiteEventService(db)
	//
	//	event, err := evSvc.Create(ctx, model.Event{UID: "evt-1", CalendarUID: cal.UID, Title: "Test Event"})
	//	require.NoError(t, err)
	//
	//	err = evSvc.Delete(ctx, event.UID)
	//	require.NoError(t, err)
	//
	//	_, ok, err := evSvc.Get(ctx, event.UID)
	//	require.NoError(t, err)
	//	require.False(t, ok)
	//})
}

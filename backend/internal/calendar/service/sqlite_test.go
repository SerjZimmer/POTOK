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
    // minimal schema (копия из InitDB)
    _, err = db.Exec(`
    CREATE TABLE calendars(uid TEXT PRIMARY KEY,name TEXT,color_hex TEXT,is_visible INTEGER,tzid_default TEXT,created_at TEXT,updated_at TEXT,deleted_at TEXT);
    CREATE TABLE events(uid TEXT PRIMARY KEY,calendar_uid TEXT,title TEXT,description TEXT,location TEXT,start_utc TEXT,end_utc TEXT,is_all_day INTEGER,tzid TEXT,recurrence_rule TEXT,created_at TEXT,updated_at TEXT,deleted_at TEXT);
    CREATE TABLE event_overrides(id INTEGER PRIMARY KEY AUTOINCREMENT,parent_uid TEXT,recurrence_id TEXT,title TEXT,description TEXT,location TEXT,start_utc TEXT,end_utc TEXT,is_all_day INTEGER,tzid TEXT,deleted_at TEXT);
    CREATE TABLE event_exdates(parent_uid TEXT, exdate TEXT, PRIMARY KEY(parent_uid,exdate));`)
    require.NoError(t, err)
    return db
}

func TestExpand_Daily_WithExdate(t *testing.T) {
    db := testDB(t)
    evSvc := NewSQLiteEventService(db)
    calSvc := NewSQLiteCalendarService(db)
    ctx := context.Background()

    // create calendar
    cal, err := calSvc.Create(ctx, model.Calendar{UID: "cal-1", Name: "Личный", ColorHex: "#FFC107", TZIDDefault: "UTC"})
    require.NoError(t, err)
    _ = cal

    // base event: daily for 5 days starting today 09:00
    start := time.Now().UTC().Truncate(24*time.Hour).Add(9 * time.Hour)
    end := start.Add(1 * time.Hour)
    rrule := "FREQ=DAILY;COUNT=5"
    _, err = evSvc.Create(ctx, model.Event{UID:"e1", CalendarUID: cal.UID, Title:"Daily", StartUTC:start, EndUTC:end, TZID:"UTC", RecurrenceRule:&rrule})
    require.NoError(t, err)

    // exdate: skip day 2
    _, err = db.Exec(`INSERT INTO event_exdates(parent_uid, exdate) VALUES (?,?)`, "e1", start.Add(24*time.Hour).Format(time.RFC3339))
    require.NoError(t, err)

    // expand window 7 days
    items, err := evSvc.Expand(ctx, start.Add(-time.Hour).Format(time.RFC3339), start.AddDate(0,0,7).Format(time.RFC3339), nil, "")
    require.NoError(t, err)
    // expected 4 occurrences (one skipped)
    cnt := 0
    for _,it := range items { if it.ParentUID != nil && *it.ParentUID == "e1" { cnt++ } }
    require.Equal(t, 4, cnt)
}

func TestApply_DeleteThis_AddsExdate(t *testing.T) {
    db := testDB(t)
    evSvc := NewSQLiteEventService(db)
    calSvc := NewSQLiteCalendarService(db)
    ctx := context.Background()
    cal, _ := calSvc.Create(ctx, model.Calendar{UID: "cal-1", Name: "Личный", ColorHex: "#FFC107", TZIDDefault: "UTC"})
    _ = cal
    start := time.Date(2025,9,1,9,0,0,0,time.UTC)
    end := start.Add(time.Hour)
    r := "FREQ=DAILY;COUNT=3"
    _, err := evSvc.Create(ctx, model.Event{UID:"e1", CalendarUID:"cal-1", Title:"x", StartUTC:start, EndUTC:end, TZID:"UTC", RecurrenceRule:&r})
    require.NoError(t, err)
    // delete middle instance
    _, err = evSvc.Apply(ctx, "e1", "delete", "this", start.Add(24*time.Hour).Format(time.RFC3339), nil)
    require.NoError(t, err)
    items, err := evSvc.Expand(ctx, start.Format(time.RFC3339), start.AddDate(0,0,5).Format(time.RFC3339), nil, "")
    require.NoError(t, err)
    cnt := 0
    for _,it := range items { if it.ParentUID != nil && *it.ParentUID == "e1" { cnt++ } }
    require.Equal(t, 2, cnt)
}

func TestApply_Following_SplitSeries(t *testing.T) {
    db := testDB(t)
    evSvc := NewSQLiteEventService(db)
    calSvc := NewSQLiteCalendarService(db)
    ctx := context.Background()
    cal, _ := calSvc.Create(ctx, model.Calendar{UID: "cal-1", Name: "Личный", ColorHex: "#FFC107", TZIDDefault: "UTC"})
    _ = cal
    start := time.Date(2025,9,1,9,0,0,0,time.UTC)
    end := start.Add(time.Hour)
    r := "FREQ=WEEKLY;BYDAY=MO;COUNT=5"
    _, err := evSvc.Create(ctx, model.Event{UID:"e1", CalendarUID:"cal-1", Title:"wk", StartUTC:start, EndUTC:end, TZID:"UTC", RecurrenceRule:&r})
    require.NoError(t, err)
    // Update following from 3rd occurrence to new time (10:00)
    rid := start.AddDate(0,0,14) // +2 weeks
    _, err = evSvc.Apply(ctx, "e1", "update", "following", rid.Format(time.RFC3339), map[string]interface{}{
        "startUtc": rid.Add(time.Hour).Format(time.RFC3339),
        "endUtc": rid.Add(2*time.Hour).Format(time.RFC3339),
        "recurrenceRule": "FREQ=WEEKLY;BYDAY=MO;COUNT=3",
    })
    require.NoError(t, err)
    items, err := evSvc.Expand(ctx, start.Add(-time.Hour).Format(time.RFC3339), start.AddDate(0,0,60).Format(time.RFC3339), nil, "")
    require.NoError(t, err)
    // Проверим, что есть инстансы до split (09:00) и после (10:00)
    early := 0; late := 0
    for _,it := range items { if it.StartUTC.Hour()==9 { early++ }; if it.StartUTC.Hour()==10 { late++ } }
    require.GreaterOrEqual(t, early, 2)
    require.GreaterOrEqual(t, late, 1)
}

func TestWeekly_ByMultipleDays_Expand(t *testing.T) {
    db := testDB(t)
    evSvc := NewSQLiteEventService(db)
    calSvc := NewSQLiteCalendarService(db)
    ctx := context.Background()
    cal, _ := calSvc.Create(ctx, model.Calendar{UID: "cal-1", Name: "Личный", ColorHex: "#FFC107", TZIDDefault: "UTC"})
    _ = cal
    start := time.Date(2025,9,1,9,0,0,0,time.UTC) // понедельник
    end := start.Add(time.Hour)
    r := "FREQ=WEEKLY;BYDAY=MO,WE,FR;COUNT=6"
    _, err := evSvc.Create(ctx, model.Event{UID:"e1", CalendarUID:"cal-1", Title:"mwf", StartUTC:start, EndUTC:end, TZID:"UTC", RecurrenceRule:&r})
    require.NoError(t, err)
    items, err := evSvc.Expand(ctx, start.Format(time.RFC3339), start.AddDate(0,0,21).Format(time.RFC3339), nil, "")
    require.NoError(t, err)
    // должно быть 6 инстансов, только в пн/ср/пт
    cnt := 0
    for _,it := range items { if it.Title=="mwf" { cnt++; wd := it.StartUTC.Weekday(); require.Contains(t, []time.Weekday{time.Monday,time.Wednesday,time.Friday}, wd) } }
    require.Equal(t, 6, cnt)
}

func TestMonthly_PositionalByDay(t *testing.T) {
    db := testDB(t); evSvc := NewSQLiteEventService(db); calSvc := NewSQLiteCalendarService(db); ctx := context.Background()
    cal, _ := calSvc.Create(ctx, model.Calendar{UID:"cal-1", Name:"Личный", ColorHex:"#FFC107", TZIDDefault:"UTC"}); _=cal
    // 1-й понедельник месяца в 09:00
    start := time.Date(2025,9,1,9,0,0,0,time.UTC) // это как раз 1-й понедельник
    end := start.Add(time.Hour)
    r := "FREQ=MONTHLY;BYDAY=1MO;COUNT=3"
    _, err := evSvc.Create(ctx, model.Event{UID:"e1", CalendarUID:"cal-1", Title:"m1mo", StartUTC:start, EndUTC:end, TZID:"UTC", RecurrenceRule:&r}); require.NoError(t, err)
    items, err := evSvc.Expand(ctx, start.Format(time.RFC3339), start.AddDate(0,3,0).Format(time.RFC3339), nil, ""); require.NoError(t, err)
    require.NotEmpty(t, items)
}

func TestYearly_ByMonth_ByMonthDay(t *testing.T) {
    db := testDB(t); evSvc := NewSQLiteEventService(db); calSvc := NewSQLiteCalendarService(db); ctx := context.Background()
    cal, _ := calSvc.Create(ctx, model.Calendar{UID:"cal-1", Name:"Личный", ColorHex:"#FFC107", TZIDDefault:"UTC"}); _=cal
    start := time.Date(2025,5,9,12,0,0,0,time.UTC)
    end := start.Add(time.Hour)
    r := "FREQ=YEARLY;BYMONTH=5;BYMONTHDAY=9;COUNT=2"
    _, err := evSvc.Create(ctx, model.Event{UID:"e1", CalendarUID:"cal-1", Title:"yr", StartUTC:start, EndUTC:end, TZID:"UTC", RecurrenceRule:&r}); require.NoError(t, err)
    items, err := evSvc.Expand(ctx, start.AddDate(0,0,-1).Format(time.RFC3339), start.AddDate(2,0,1).Format(time.RFC3339), nil, ""); require.NoError(t, err)
    // Должно быть 2 вхождения за 2 года
    cnt := 0; for _,it := range items { if it.Title=="yr" { cnt++ } }
    require.Equal(t, 2, cnt)
}

func TestApply_DeleteFollowing_RemovesTail(t *testing.T) {
    db := testDB(t); evSvc := NewSQLiteEventService(db); calSvc := NewSQLiteCalendarService(db); ctx := context.Background()
    cal, _ := calSvc.Create(ctx, model.Calendar{UID:"cal-1", Name:"Личный", ColorHex:"#FFC107", TZIDDefault:"UTC"}); _=cal
    start := time.Date(2025,9,1,9,0,0,0,time.UTC)
    end := start.Add(time.Hour)
    r := "FREQ=DAILY;COUNT=5"
    _, err := evSvc.Create(ctx, model.Event{UID:"e1", CalendarUID:"cal-1", Title:"d", StartUTC:start, EndUTC:end, TZID:"UTC", RecurrenceRule:&r}); require.NoError(t, err)
    // удалить последующие начиная с 3-го дня
    rid := start.AddDate(0,0,2)
    _, err = evSvc.Apply(ctx, "e1", "delete", "following", rid.Format(time.RFC3339), nil)
    require.NoError(t, err)
    items, err := evSvc.Expand(ctx, start.Format(time.RFC3339), start.AddDate(0,0,10).Format(time.RFC3339), nil, "")
    require.NoError(t, err)
    cnt := 0; for _,it := range items { if it.ParentUID != nil && *it.ParentUID == "e1" { cnt++ } }
    require.Equal(t, 2, cnt) // осталось только первые два
}

func TestApply_UpdateThis_Override(t *testing.T) {
    db := testDB(t); evSvc := NewSQLiteEventService(db); calSvc := NewSQLiteCalendarService(db); ctx := context.Background()
    cal, _ := calSvc.Create(ctx, model.Calendar{UID:"cal-1", Name:"Личный", ColorHex:"#FFC107", TZIDDefault:"UTC"}); _=cal
    start := time.Date(2025,9,1,9,0,0,0,time.UTC)
    end := start.Add(time.Hour)
    r := "FREQ=DAILY;COUNT=3"
    _, err := evSvc.Create(ctx, model.Event{UID:"e1", CalendarUID:"cal-1", Title:"t", StartUTC:start, EndUTC:end, TZID:"UTC", RecurrenceRule:&r}); require.NoError(t, err)
    rid := start.AddDate(0,0,1)
    _, err = evSvc.Apply(ctx, "e1", "update", "this", rid.Format(time.RFC3339), map[string]interface{}{
        "title": "override",
        "startUtc": rid.Add(30*time.Minute).Format(time.RFC3339),
        "endUtc": rid.Add(90*time.Minute).Format(time.RFC3339),
        "tzid": "UTC",
    })
    require.NoError(t, err)
    items, err := evSvc.Expand(ctx, start.Add(-time.Hour).Format(time.RFC3339), start.AddDate(0,0,5).Format(time.RFC3339), nil, "")
    require.NoError(t, err)
    var found bool
    for _,it := range items { if it.Title=="override" { found = true; require.Equal(t, 9, it.StartUTC.Hour()); require.Equal(t, 30, it.StartUTC.Minute()); break } }
    require.True(t, found)
}

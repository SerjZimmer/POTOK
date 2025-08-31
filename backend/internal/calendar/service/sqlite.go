// Пакет service содержит бизнес‑логику календаря. Данный файл — реализация
// CalendarService/EventService поверх SQLite (та же БД, что используется для
// модуля «Заметки»). Цель: вся логика повторов/серий/override находится на
// сервере, клиент лишь отображает и отправляет команды.
//
// Ключевые принципы:
// - Все времена в UTC; клиент отвечает за локализацию при вводе/выводе.
// - Экспансия инстансов делается на сервере по полуинтервалу [start,end).
// - Операции над серией:
//   update/delete series — меняют/помечают базовое событие;
//   update/delete this — создают/используют override (или EXDATE для delete);
//   update/delete following — «разрезают» RRULE (UNTIL) и, при update,
//     создают новую серию на «хвосте» с параметрами из patch.
package service

import (
    "context"
    "database/sql"
    "errors"
    "sort"
    "strings"
    "time"

    "github.com/google/uuid"
    "potok/backend/internal/calendar/model"
    "potok/backend/internal/calendar/rrule"
)

// SQLite implementations. Таблицы создаются в db.InitDB.

type sqliteCalendarService struct { db *sql.DB }
type sqliteEventService struct { db *sql.DB }

func NewSQLiteCalendarService(db *sql.DB) CalendarService { return &sqliteCalendarService{db: db} }
func NewSQLiteEventService(db *sql.DB) EventService { return &sqliteEventService{db: db} }

// Calendars
func (s *sqliteCalendarService) List(ctx context.Context, limit int, cursor string) ([]model.Calendar, *model.PageMeta, error) {
    rows, err := s.db.QueryContext(ctx, `SELECT uid,name,color_hex,is_visible,tzid_default,created_at,updated_at,deleted_at FROM calendars WHERE deleted_at IS NULL`)
    if err != nil { return nil, nil, err }
    defer rows.Close()
    out := []model.Calendar{}
    for rows.Next() {
        var c model.Calendar; var isVisible int; var created, updated string; var deleted sql.NullString
        if err := rows.Scan(&c.UID,&c.Name,&c.ColorHex,&isVisible,&c.TZIDDefault,&created,&updated,&deleted); err!=nil { return nil,nil,err }
        c.IsVisible = isVisible==1
        c.CreatedAt, _ = time.Parse(time.RFC3339, created)
        c.UpdatedAt, _ = time.Parse(time.RFC3339, updated)
        if deleted.Valid { t,_ := time.Parse(time.RFC3339, deleted.String); c.DeletedAt=&t }
        out = append(out, c)
    }
    return out, &model.PageMeta{Limit: limit}, nil
}
func (s *sqliteCalendarService) Create(ctx context.Context, c model.Calendar) (model.Calendar, error) {
    if c.UID=="" { c.UID = uuid.New().String() }
    if c.ColorHex=="" { c.ColorHex="#FFC107" }
    if c.TZIDDefault=="" { c.TZIDDefault="UTC" }
    now := time.Now().UTC(); c.CreatedAt, c.UpdatedAt = now, now; if c.IsVisible==false { c.IsVisible = true }
    _, err := s.db.ExecContext(ctx, `INSERT INTO calendars(uid,name,color_hex,is_visible,tzid_default,created_at,updated_at) VALUES (?,?,?,?,?,?,?)`, c.UID, c.Name, c.ColorHex, boolToInt(c.IsVisible), c.TZIDDefault, c.CreatedAt.Format(time.RFC3339), c.UpdatedAt.Format(time.RFC3339))
    return c, err
}
func (s *sqliteCalendarService) Get(ctx context.Context, uid string) (model.Calendar, bool, error) {
    row := s.db.QueryRowContext(ctx, `SELECT uid,name,color_hex,is_visible,tzid_default,created_at,updated_at,deleted_at FROM calendars WHERE uid=?`, uid)
    var c model.Calendar; var isVisible int; var created, updated string; var deleted sql.NullString
    if err := row.Scan(&c.UID,&c.Name,&c.ColorHex,&isVisible,&c.TZIDDefault,&created,&updated,&deleted); err!=nil { if errors.Is(err, sql.ErrNoRows){return model.Calendar{}, false, nil}; return model.Calendar{}, false, err }
    c.IsVisible = isVisible==1; c.CreatedAt,_ = time.Parse(time.RFC3339,created); c.UpdatedAt,_=time.Parse(time.RFC3339,updated); if deleted.Valid { t,_:=time.Parse(time.RFC3339,deleted.String); c.DeletedAt=&t }
    return c, true, nil
}
func (s *sqliteCalendarService) Patch(ctx context.Context, uid string, patch map[string]interface{}, ifMatch string) (model.Calendar, error) {
    c, ok, err := s.Get(ctx, uid); if err!=nil { return model.Calendar{}, err }; if !ok { return model.Calendar{}, errors.New("not found") }
    if v,ok := patch["name"].(string); ok { c.Name=v }
    if v,ok := patch["colorHex"].(string); ok { c.ColorHex=v }
    c.UpdatedAt = time.Now().UTC()
    _, err = s.db.ExecContext(ctx, `UPDATE calendars SET name=?, color_hex=?, updated_at=? WHERE uid=?`, c.Name, c.ColorHex, c.UpdatedAt.Format(time.RFC3339), uid)
    return c, err
}
func (s *sqliteCalendarService) Delete(ctx context.Context, uid string) error {
    _, err := s.db.ExecContext(ctx, `UPDATE calendars SET deleted_at=? WHERE uid=?`, time.Now().UTC().Format(time.RFC3339), uid)
    return err
}

// Events
func (s *sqliteEventService) List(ctx context.Context, filter map[string]interface{}) ([]model.Event, *model.PageMeta, error) {
    rows, err := s.db.QueryContext(ctx, `SELECT uid,calendar_uid,title,description,location,start_utc,end_utc,is_all_day,tzid,recurrence_rule,created_at,updated_at,deleted_at FROM events WHERE deleted_at IS NULL`)
    if err!=nil { return nil,nil,err }
    defer rows.Close()
    out := []model.Event{}
    for rows.Next() { out = append(out, scanEvent(rows)) }
    return out, &model.PageMeta{Limit:50}, nil
}
func scanEvent(row interface{ Scan(dest ...any) error }) model.Event {
    var e model.Event; var desc,loc,rrule,deleted sql.NullString; var isAll int; var created,updated string; var sStart, sEnd string
    _ = row.Scan(&e.UID,&e.CalendarUID,&e.Title,&desc,&loc,&sStart,&sEnd,&isAll,&e.TZID,&rrule,&created,&updated,&deleted)
    e.StartUTC, _ = time.Parse(time.RFC3339, sStart)
    e.EndUTC, _ = time.Parse(time.RFC3339, sEnd)
    if desc.Valid { e.Description=&desc.String }
    if loc.Valid { e.Location=&loc.String }
    e.IsAllDay = isAll==1
    if rrule.Valid { e.RecurrenceRule=&rrule.String }
    e.CreatedAt,_ = time.Parse(time.RFC3339, created)
    e.UpdatedAt,_ = time.Parse(time.RFC3339, updated)
    if deleted.Valid { t,_ := time.Parse(time.RFC3339, deleted.String); e.DeletedAt = &t }
    return e
}
func (s *sqliteEventService) Create(ctx context.Context, e model.Event) (model.Event, error) {
    if e.UID=="" { e.UID = uuid.New().String() }
    now := time.Now().UTC(); e.CreatedAt, e.UpdatedAt = now, now
    _, err := s.db.ExecContext(ctx, `INSERT INTO events(uid,calendar_uid,title,description,location,start_utc,end_utc,is_all_day,tzid,recurrence_rule,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)`, e.UID,e.CalendarUID,e.Title,e.Description,e.Location,e.StartUTC.Format(time.RFC3339),e.EndUTC.Format(time.RFC3339),boolToInt(e.IsAllDay),e.TZID,e.RecurrenceRule,e.CreatedAt.Format(time.RFC3339),e.UpdatedAt.Format(time.RFC3339))
    return e, err
}
func (s *sqliteEventService) Get(ctx context.Context, uid string) (model.Event, bool, error) {
    row := s.db.QueryRowContext(ctx, `SELECT uid,calendar_uid,title,description,location,start_utc,end_utc,is_all_day,tzid,recurrence_rule,created_at,updated_at,deleted_at FROM events WHERE uid=?`, uid)
    var e = scanEvent(row)
    if e.UID=="" { return model.Event{}, false, nil }
    // exdates
    ed, _ := s.db.QueryContext(ctx, `SELECT exdate FROM event_exdates WHERE parent_uid=?`, uid)
    defer ed.Close()
    for ed.Next() { var sdt string; _ = ed.Scan(&sdt); if t,err := time.Parse(time.RFC3339, sdt); err==nil { e.Exdates = append(e.Exdates, t) } }
    return e, true, nil
}
func (s *sqliteEventService) Patch(ctx context.Context, uid string, patch map[string]interface{}, ifMatch string) (model.Event, error) {
    e, ok, err := s.Get(ctx, uid); if err!=nil { return model.Event{}, err }; if !ok { return model.Event{}, errors.New("not found") }
    if v,ok := patch["title"].(string); ok { e.Title=v }
    if v,ok := patch["description"].(string); ok { e.Description=&v }
    if v,ok := patch["location"].(string); ok { e.Location=&v }
    if v,ok := patch["calendarUid"].(string); ok { e.CalendarUID=v }
    if v,ok := patch["startUtc"].(string); ok { if t,err := time.Parse(time.RFC3339, v); err==nil { e.StartUTC=t } }
    if v,ok := patch["endUtc"].(string); ok { if t,err := time.Parse(time.RFC3339, v); err==nil { e.EndUTC=t } }
    if v,ok := patch["isAllDay"].(bool); ok { e.IsAllDay=v }
    if v,ok := patch["tzid"].(string); ok { e.TZID=v }
    if v,ok := patch["recurrenceRule"].(string); ok { if v=="" { e.RecurrenceRule=nil } else { e.RecurrenceRule=&v } }
    e.UpdatedAt = time.Now().UTC()
    _, err = s.db.ExecContext(ctx, `UPDATE events SET calendar_uid=?, title=?, description=?, location=?, start_utc=?, end_utc=?, is_all_day=?, tzid=?, recurrence_rule=?, updated_at=? WHERE uid=?`, e.CalendarUID,e.Title,e.Description,e.Location,e.StartUTC.Format(time.RFC3339),e.EndUTC.Format(time.RFC3339),boolToInt(e.IsAllDay),e.TZID,e.RecurrenceRule,e.UpdatedAt.Format(time.RFC3339), uid)
    return e, err
}
func (s *sqliteEventService) Delete(ctx context.Context, uid string) error {
    _, err := s.db.ExecContext(ctx, `UPDATE events SET deleted_at=? WHERE uid=?`, time.Now().UTC().Format(time.RFC3339), uid)
    return err
}

// Expand and Apply delegate logic to in-memory helpers for now, but read/write through SQLite
func (s *sqliteEventService) Expand(ctx context.Context, timeMinISO, timeMaxISO string, calendarUids []string, q string) ([]model.Event, error) {
    // Экспансия выполняется в 3 шага:
    // 1) Выбираем из БД базовые события‑кандидаты (серии и одиночные) с фильтрами.
    // 2) Для каждой серии подгружаем EXDATE и overrides.
    // 3) Разворачиваем RRULE в окне [timeMin, timeMax) и собираем инстансы,
    //    подменяя их override‑ами и отфильтровывая EXDATE.
    timeMin, _ := time.Parse(time.RFC3339, timeMinISO)
    timeMax, _ := time.Parse(time.RFC3339, timeMaxISO)
    // Fetch candidate base events (simple filter: in calendars and (overlap window or has RRULE))
    where := []string{"deleted_at IS NULL"}
    args := []any{}
    if len(calendarUids)>0 {
        where = append(where, "calendar_uid IN ("+placeholders(len(calendarUids))+")")
        for _,c := range calendarUids { args = append(args, c) }
    }
    // crude overlap or recurring
    where = append(where, "(recurrence_rule IS NOT NULL OR (start_utc < ? AND end_utc > ?))")
    args = append(args, timeMax.Format(time.RFC3339), timeMin.Format(time.RFC3339))
    query := `SELECT uid,calendar_uid,title,description,location,start_utc,end_utc,is_all_day,tzid,recurrence_rule,created_at,updated_at,deleted_at FROM events WHERE `+strings.Join(where, " AND ")
    rows, err := s.db.QueryContext(ctx, query, args...)
    if err!=nil { return nil, err }
    defer rows.Close()
    bases := []model.Event{}
    for rows.Next() { bases = append(bases, scanEvent(rows)) }
    // load overrides for parents in window
    out := []model.Event{}
    for _,e := range bases {
        // exdates
        edRows, _ := s.db.QueryContext(ctx, `SELECT exdate FROM event_exdates WHERE parent_uid=?`, e.UID)
        for edRows.Next() { var sdt string; _ = edRows.Scan(&sdt); if t,err := time.Parse(time.RFC3339,sdt); err==nil { e.Exdates = append(e.Exdates, t) } }
        edRows.Close()
        if e.RecurrenceRule==nil || *e.RecurrenceRule=="" {
            if e.StartUTC.Before(timeMax) && e.EndUTC.After(timeMin) { out = append(out, e) }
            continue
        }
        occ := rrule.ExpandOccurrences(rrule.EventSpec{StartUTC:e.StartUTC, EndUTC:e.EndUTC, Rule:*e.RecurrenceRule, Exdates:e.Exdates}, timeMin, timeMax)
        dur := e.EndUTC.Sub(e.StartUTC)
        // overrides for this parent
        ovRows, _ := s.db.QueryContext(ctx, `SELECT title,description,location,start_utc,end_utc,is_all_day,tzid,recurrence_id,deleted_at FROM event_overrides WHERE parent_uid=?`, e.UID)
        overrides := map[string]model.Event{}
        for ovRows.Next(){ var tTitle, tDesc, tLoc, tStart, tEnd, tTz, rid string; var del sql.NullString; var isAll sql.NullInt64
            _ = ovRows.Scan(&tTitle,&tDesc,&tLoc,&tStart,&tEnd,&isAll,&tTz,&rid,&del)
            ov := e
            if tTitle!="" { ov.Title=tTitle }
            if tDesc!="" { ov.Description=&tDesc }
            if tLoc!="" { ov.Location=&tLoc }
            if tStart!="" { ov.StartUTC,_=time.Parse(time.RFC3339,tStart) }
            if tEnd!="" { ov.EndUTC,_=time.Parse(time.RFC3339,tEnd) }
            if isAll.Valid { ov.IsAllDay = isAll.Int64==1 }
            if tTz!="" { ov.TZID=tTz }
            ov.ParentUID = &e.UID
            ov.RecurrenceID = &rid
            if del.Valid { t,_ := time.Parse(time.RFC3339, del.String); ov.DeletedAt = &t }
            overrides[rid] = ov
        }
        ovRows.Close()
        for _,o := range occ {
            rid := o.Format(time.RFC3339)
            if ov,ok := overrides[rid]; ok {
                if ov.DeletedAt==nil { out = append(out, ov) }
            } else {
                inst := e
                inst.StartUTC = o; inst.EndUTC = o.Add(dur)
                pid := e.UID; inst.ParentUID = &pid
                ridCopy := rid; inst.RecurrenceID = &ridCopy
                out = append(out, inst)
            }
        }
    }
    sort.Slice(out, func(i,j int) bool { return out[i].StartUTC.Before(out[j].StartUTC) })
    return out, nil
}

func (s *sqliteEventService) Apply(ctx context.Context, uid, action, scope, recurrenceID string, patch map[string]interface{}) (interface{}, error) {
    // Единая точка входа для «скоупленных» операций. Возвращает результат,
    // подходящий для UI (например, новую серию при update/following) или
    // простой статус.
    switch action {
    case "delete":
        if scope=="series" { return nil, s.Delete(ctx, uid) } // soft delete
        if recurrenceID=="" { return nil, errors.New("recurrenceId required") }
        if scope=="this" { // EXDATE — скрыть один инстанс без override
            _,err := s.db.ExecContext(ctx, `INSERT OR IGNORE INTO event_exdates(parent_uid, exdate) VALUES (?,?)`, uid, recurrenceID)
            return map[string]string{"status":"deleted_this"}, err
        }
        if scope=="following" {
            rid, _ := time.Parse(time.RFC3339, recurrenceID); until := rid.Add(-1*time.Second)
            base,ok,err := s.Get(ctx, uid); if err!=nil || !ok { return nil, errors.New("not found") }
            rr := rrule.WithUntil(ptrTo(base.RecurrenceRule), until)
            _,err = s.db.ExecContext(ctx, `UPDATE events SET recurrence_rule=?, updated_at=? WHERE uid=?`, rr, time.Now().UTC().Format(time.RFC3339), uid)
            if err!=nil { return nil, err }
            // Удаляем override‑ы на и после точки split — они относятся к
            // «хвосту», который теперь отсутствует
            _,_ = s.db.ExecContext(ctx, `DELETE FROM event_overrides WHERE parent_uid=? AND recurrence_id>=?`, uid, recurrenceID)
            return map[string]string{"status":"deleted_following"}, nil
        }
    case "update":
        if scope=="series" { // частичное обновление базовой записи
            return s.Patch(ctx, uid, patch, "")
        }
        if recurrenceID=="" { return nil, errors.New("recurrenceId required") }
        if scope=="this" {
            // upsert override — индивидуальные изменения для одного инстанса
            _,err := s.db.ExecContext(ctx, `INSERT INTO event_overrides(parent_uid,recurrence_id,title,description,location,start_utc,end_utc,is_all_day,tzid) VALUES (?,?,?,?,?,?,?,?,?)`, uid, recurrenceID, patch["title"], patch["description"], patch["location"], patch["startUtc"], patch["endUtc"], toNullInt(patch["isAllDay"]), patch["tzid"])
            if err!=nil { // try update
                _,err = s.db.ExecContext(ctx, `UPDATE event_overrides SET title=?,description=?,location=?,start_utc=?,end_utc=?,is_all_day=?,tzid=?, deleted_at=NULL WHERE parent_uid=? AND recurrence_id=?`, patch["title"],patch["description"],patch["location"],patch["startUtc"],patch["endUtc"],toNullInt(patch["isAllDay"]),patch["tzid"], uid, recurrenceID)
            }
            return map[string]string{"status":"updated_this"}, err
        }
        if scope=="following" {
            rid, _ := time.Parse(time.RFC3339, recurrenceID); until := rid.Add(-1*time.Second)
            base,ok,err := s.Get(ctx, uid); if err!=nil || !ok { return nil, errors.New("not found") }
            rr := rrule.WithUntil(ptrTo(base.RecurrenceRule), until)
            _,err = s.db.ExecContext(ctx, `UPDATE events SET recurrence_rule=?, updated_at=? WHERE uid=?`, rr, time.Now().UTC().Format(time.RFC3339), uid)
            if err!=nil { return nil, err }
            // Создаём новую серию на «хвосте», применяя patch
            ns := base; ns.UID = uuid.New().String()
            if v,ok := patch["title"].(string); ok { ns.Title=v }
            if v,ok := patch["description"].(string); ok { ns.Description=&v }
            if v,ok := patch["location"].(string); ok { ns.Location=&v }
            if v,ok := patch["startUtc"].(string); ok { if t,err:=time.Parse(time.RFC3339,v); err==nil { ns.StartUTC=t } }
            if v,ok := patch["endUtc"].(string); ok { if t,err:=time.Parse(time.RFC3339,v); err==nil { ns.EndUTC=t } }
            if v,ok := patch["recurrenceRule"].(string); ok { ns.RecurrenceRule=&v }
            ns.CreatedAt, ns.UpdatedAt = time.Now().UTC(), time.Now().UTC()
            _,err = s.db.ExecContext(ctx, `INSERT INTO events(uid,calendar_uid,title,description,location,start_utc,end_utc,is_all_day,tzid,recurrence_rule,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)`, ns.UID, ns.CalendarUID, ns.Title, ns.Description, ns.Location, ns.StartUTC.Format(time.RFC3339), ns.EndUTC.Format(time.RFC3339), boolToInt(ns.IsAllDay), ns.TZID, ns.RecurrenceRule, ns.CreatedAt.Format(time.RFC3339), ns.UpdatedAt.Format(time.RFC3339))
            if err!=nil { return nil, err }
            return ns, nil
        }
    }
    return nil, errors.New("unsupported action/scope")
}

// utils
func boolToInt(b bool) int { if b { return 1 }; return 0 }
func placeholders(n int) string { if n<=0 { return "" }; s:=make([]string,n); for i:=0;i<n;i++ { s[i] = "?" }; return strings.Join(s,",") }
func toNullInt(v interface{}) interface{} { if v==nil { return nil }; if b,ok := v.(bool); ok { if b { return 1 }; return 0 }; return v }
func ptrTo(p *string) string { if p==nil { return "" }; return *p }

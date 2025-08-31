package service

import (
    "context"
    "errors"
    "sort"
    "strings"
    "time"
    "strconv"

    "github.com/google/uuid"
    "potok/backend/internal/calendar/model"
)

// In-memory implementations for fast prototyping. Replace with DB later.

type inMemoryCalendarService struct { calendars map[string]model.Calendar }
type inMemoryEventService struct { events map[string]model.Event; overrides map[string]model.Event }

func NewInMemoryCalendarService() CalendarService {
    return &inMemoryCalendarService{calendars: map[string]model.Calendar{}}
}
func NewInMemoryEventService() EventService {
    return &inMemoryEventService{events: map[string]model.Event{}, overrides: map[string]model.Event{}}
}

// ---- Calendars ----
func (s *inMemoryCalendarService) List(ctx context.Context, limit int, cursor string) ([]model.Calendar, *model.PageMeta, error) {
    out := make([]model.Calendar, 0, len(s.calendars))
    for _, c := range s.calendars { out = append(out, c) }
    sort.Slice(out, func(i,j int) bool { return out[i].CreatedAt.Before(out[j].CreatedAt) })
    return out, &model.PageMeta{Limit: limit}, nil
}
func (s *inMemoryCalendarService) Create(ctx context.Context, c model.Calendar) (model.Calendar, error) {
    if c.UID == "" { c.UID = uuid.New().String() }
    now := time.Now().UTC(); c.CreatedAt, c.UpdatedAt = now, now
    if c.ColorHex == "" { c.ColorHex = "#FFC107" }
    if c.TZIDDefault == "" { c.TZIDDefault = "UTC" }
    s.calendars[c.UID] = c
    return c, nil
}
func (s *inMemoryCalendarService) Get(ctx context.Context, uid string) (model.Calendar, bool, error) {
    c, ok := s.calendars[uid]
    return c, ok, nil
}
func (s *inMemoryCalendarService) Patch(ctx context.Context, uid string, patch map[string]interface{}, ifMatch string) (model.Calendar, error) {
    c, ok := s.calendars[uid]; if !ok { return model.Calendar{}, errors.New("not found") }
    if v,ok := patch["name"].(string); ok { c.Name = v }
    if v,ok := patch["colorHex"].(string); ok { c.ColorHex = v }
    now := time.Now().UTC(); c.UpdatedAt = now
    s.calendars[uid] = c
    return c, nil
}
func (s *inMemoryCalendarService) Delete(ctx context.Context, uid string) error { delete(s.calendars, uid); return nil }

// ---- Events ----
func (s *inMemoryEventService) List(ctx context.Context, filter map[string]interface{}) ([]model.Event, *model.PageMeta, error) {
    out := make([]model.Event, 0, len(s.events))
    for _, e := range s.events { out = append(out, e) }
    return out, &model.PageMeta{Limit:50}, nil
}
func (s *inMemoryEventService) Create(ctx context.Context, e model.Event) (model.Event, error) {
    if e.UID == "" { e.UID = uuid.New().String() }
    now := time.Now().UTC(); e.CreatedAt, e.UpdatedAt = now, now
    s.events[e.UID] = e
    return e, nil
}
func (s *inMemoryEventService) Get(ctx context.Context, uid string) (model.Event, bool, error) {
    e, ok := s.events[uid]; return e, ok, nil
}
func (s *inMemoryEventService) Patch(ctx context.Context, uid string, patch map[string]interface{}, ifMatch string) (model.Event, error) {
    e, ok := s.events[uid]; if !ok { return model.Event{}, errors.New("not found") }
    if v,ok := patch["title"].(string); ok { e.Title = v }
    if v,ok := patch["description"].(string); ok { e.Description = &v }
    if v,ok := patch["location"].(string); ok { e.Location = &v }
    if v,ok := patch["calendarUid"].(string); ok { e.CalendarUID = v }
    if v,ok := patch["startUtc"].(string); ok { if t,err := time.Parse(time.RFC3339, v); err==nil { e.StartUTC = t } }
    if v,ok := patch["endUtc"].(string); ok { if t,err := time.Parse(time.RFC3339, v); err==nil { e.EndUTC = t } }
    if v,ok := patch["isAllDay"].(bool); ok { e.IsAllDay = v }
    if v,ok := patch["tzid"].(string); ok { e.TZID = v }
    if v,ok := patch["recurrenceRule"].(string); ok { if v=="" { e.RecurrenceRule = nil } else { e.RecurrenceRule = &v } }
    now := time.Now().UTC(); e.UpdatedAt = now
    s.events[uid] = e
    return e, nil
}
func (s *inMemoryEventService) Delete(ctx context.Context, uid string) error {
    delete(s.events, uid)
    // delete overrides of this parent
    for k,ov := range s.overrides { if ov.ParentUID != nil && *ov.ParentUID == uid { delete(s.overrides, k) } }
    return nil
}

// Expand occurrences in [timeMin,timeMax)
func (s *inMemoryEventService) Expand(ctx context.Context, timeMinISO, timeMaxISO string, calendarUids []string, q string) ([]model.Event, error) {
    timeMin, err := time.Parse(time.RFC3339, timeMinISO); if err != nil { return nil, err }
    timeMax, err := time.Parse(time.RFC3339, timeMaxISO); if err != nil { return nil, err }
    useCalFilter := len(calendarUids) > 0
    calSet := map[string]struct{}{}
    for _,c := range calendarUids { calSet[c]=struct{}{} }
    out := []model.Event{}
    for _, e := range s.events {
        if useCalFilter { if _,ok := calSet[e.CalendarUID]; !ok { continue } }
        if q != "" && !strings.Contains(strings.ToLower(e.Title), strings.ToLower(q)) { continue }
        if e.RecurrenceRule == nil || *e.RecurrenceRule == "" {
            if e.StartUTC.Before(timeMax) && e.EndUTC.After(timeMin) {
                out = append(out, e)
            }
            continue
        }
        occ := expandOccurrences(e, timeMin, timeMax)
        dur := e.EndUTC.Sub(e.StartUTC)
        for _, o := range occ {
            rid := o.Format(time.RFC3339)
            // override lookup
            var ov *model.Event
            for _,v := range s.overrides {
                if v.ParentUID != nil && *v.ParentUID == e.UID && v.RecurrenceID != nil && *v.RecurrenceID == rid { ov = &v; break }
            }
            if ov != nil {
                if ov.DeletedAt == nil { out = append(out, *ov) }
            } else {
                inst := e
                inst.StartUTC = o
                inst.EndUTC = o.Add(dur)
                r := e.RecurrenceRule
                inst.RecurrenceRule = r
                pid := e.UID; inst.ParentUID = &pid
                ridCopy := rid; inst.RecurrenceID = &ridCopy
                out = append(out, inst)
            }
        }
    }
    sort.Slice(out, func(i,j int) bool { return out[i].StartUTC.Before(out[j].StartUTC) })
    return out, nil
}

// Apply scoped action. For MVP: delete(this|following|series), update(series) and update(this|following) by creating override/new series
func (s *inMemoryEventService) Apply(ctx context.Context, uid, action, scope, recurrenceID string, patch map[string]interface{}) (interface{}, error) {
    e, ok := s.events[uid]
    if !ok { return nil, errors.New("event not found") }
    switch action {
    case "delete":
        switch scope {
        case "series":
            return nil, s.Delete(ctx, uid)
        case "this":
            if recurrenceID == "" { return nil, errors.New("recurrenceId required") }
            // Добавляем EXDATE в базовую серию
            e.Exdates = append(e.Exdates, mustParse(recurrenceID))
            s.events[uid] = e
            return map[string]string{"status":"deleted_this"}, nil
        case "following":
            if recurrenceID == "" { return nil, errors.New("recurrenceId required") }
            // cut series until recurrenceID-1s
            rid := mustParse(recurrenceID)
            until := rid.Add(-1 * time.Second)
            rr := withUntil(e, until)
            e.RecurrenceRule = &rr
            s.events[uid] = e
            // remove overrides at/after split
            for k,ov := range s.overrides { if ov.ParentUID != nil && *ov.ParentUID == uid { if ov.RecurrenceID != nil { if !mustParse(*ov.RecurrenceID).Before(rid) { delete(s.overrides, k) }}}}
            return map[string]string{"status":"deleted_following"}, nil
        }
    case "update":
        switch scope {
        case "series":
            return s.Patch(ctx, uid, patch, "")
        case "this":
            if recurrenceID == "" { return nil, errors.New("recurrenceId required") }
            // upsert override
            ov := e
            if v,ok := patch["title"].(string); ok { ov.Title = v }
            if v,ok := patch["description"].(string); ok { ov.Description = &v }
            if v,ok := patch["location"].(string); ok { ov.Location = &v }
            if v,ok := patch["startUtc"].(string); ok { if t,err := time.Parse(time.RFC3339, v); err==nil { ov.StartUTC = t } }
            if v,ok := patch["endUtc"].(string); ok { if t,err := time.Parse(time.RFC3339, v); err==nil { ov.EndUTC = t } }
            ov.ParentUID = &e.UID
            rid := recurrenceID; ov.RecurrenceID = &rid
            ov.RecurrenceRule = nil
            s.overrides[uuid.New().String()] = ov
            return ov, nil
        case "following":
            if recurrenceID == "" { return nil, errors.New("recurrenceId required") }
            // cut original and create a new series starting at recurrenceID
            rid := mustParse(recurrenceID)
            until := rid.Add(-1 * time.Second)
            rr := withUntil(e, until)
            e.RecurrenceRule = &rr
            s.events[uid] = e
            // new series from patch
            ns := e
            ns.UID = uuid.New().String()
            ns.StartUTC = e.StartUTC // may be overridden by patch
            if v,ok := patch["title"].(string); ok { ns.Title = v }
            if v,ok := patch["description"].(string); ok { ns.Description = &v }
            if v,ok := patch["location"].(string); ok { ns.Location = &v }
            if v,ok := patch["startUtc"].(string); ok { if t,err := time.Parse(time.RFC3339, v); err==nil { ns.StartUTC = t } }
            if v,ok := patch["endUtc"].(string); ok { if t,err := time.Parse(time.RFC3339, v); err==nil { ns.EndUTC = t } }
            if v,ok := patch["recurrenceRule"].(string); ok { ns.RecurrenceRule = &v }
            now := time.Now().UTC(); ns.CreatedAt, ns.UpdatedAt = now, now
            s.events[ns.UID] = ns
            return ns, nil
        }
    }
    return nil, errors.New("unsupported action/scope")
}

// ---- RRULE helpers (minimal) ----

func expandOccurrences(e model.Event, windowStart, windowEnd time.Time) []time.Time {
    // Support: DAILY/WEEKLY/MONTHLY(by monthday)/YEARLY; INTERVAL; BYDAY in WEEKLY; BYMONTH; BYMONTHDAY; UNTIL/COUNT
    if e.RecurrenceRule == nil || *e.RecurrenceRule == "" { return nil }
    rule := parseRRule(*e.RecurrenceRule)
    freq := strings.ToUpper(rule["FREQ"]) ; if freq=="" { freq="DAILY" }
    interval := atoi(rule["INTERVAL"], 1)
    until := parseTime(rule["UNTIL"]) // may be zero
    count := atoi(rule["COUNT"], 0)
    byday := parseList(rule["BYDAY"]) // e.g. MO,TU
    bymonthday := parseIntList(rule["BYMONTHDAY"]) // 1..31
    // bymonth not used in in-memory YEARLY; kept in SQLite RRULE

    exset := map[string]struct{}{}
    for _, d := range e.Exdates { exset[d.UTC().Format(time.RFC3339)] = struct{}{} }

    var out []time.Time
    dtStart := e.StartUTC
    // don't generate before start
    add := func(t time.Time){
        if !t.Before(dtStart) && !t.Before(windowStart) && t.Before(windowEnd) {
            if _,skip := exset[t.Format(time.RFC3339)]; !skip { out = append(out, t) }
        }
    }

    switch freq {
    case "DAILY":
        cur := alignDaily(dtStart, interval, windowStart)
        for beforeEnd(cur, until, count, len(out)) && cur.Before(windowEnd) { add(cur); cur = cur.AddDate(0,0,interval) }
    case "WEEKLY":
        wds := weekdaysOrDefault(byday, dtStart.Weekday())
        weekStart := weekStartOf(windowStart)
        for beforeEnd(weekStart, until, count, len(out)) && weekStart.Before(windowEnd) {
            for _,wd := range wds {
                d := weekStart.AddDate(0,0,int(wd-1))
                occ := time.Date(d.Year(), d.Month(), d.Day(), dtStart.Hour(), dtStart.Minute(), dtStart.Second(), 0, time.UTC)
                add(occ)
            }
            weekStart = weekStart.AddDate(0,0,7*interval)
        }
        sort.Slice(out, func(i,j int) bool { return out[i].Before(out[j]) })
        if count>0 && len(out)>count { out = out[:count] }
    case "MONTHLY":
        cur := time.Date(windowStart.Year(), windowStart.Month(), 1, dtStart.Hour(), dtStart.Minute(), dtStart.Second(), 0, time.UTC)
        for beforeEnd(cur, until, count, len(out)) && cur.Before(windowEnd) {
            // position BYDAY like 1MO or -1SU
            if pos,wd, ok := parsePositionalByDay(rule["BYDAY"]); ok {
                d := nthWeekdayOfMonth(cur.Year(), int(cur.Month()), wd, pos)
                occ := time.Date(cur.Year(), cur.Month(), d, dtStart.Hour(), dtStart.Minute(), dtStart.Second(), 0, time.UTC)
                add(occ)
            } else if len(bymonthday)>0 {
                for _,md := range bymonthday { if md>=1 && md<=31 { occ:=time.Date(cur.Year(),cur.Month(),md,dtStart.Hour(),dtStart.Minute(),dtStart.Second(),0,time.UTC); add(occ) } }
            } else {
                occ := time.Date(cur.Year(), cur.Month(), dtStart.Day(), dtStart.Hour(), dtStart.Minute(), dtStart.Second(), 0, time.UTC)
                add(occ)
            }
            cur = cur.AddDate(0,interval,0)
        }
    case "YEARLY":
        y := windowStart.Year()
        for {
            occ := time.Date(y, dtStart.Month(), dtStart.Day(), dtStart.Hour(), dtStart.Minute(), dtStart.Second(), 0, time.UTC)
            if !beforeEnd(occ, until, count, len(out)) || occ.After(windowEnd) { break }
            add(occ); y += interval
        }
    default:
        // single fallback
        if dtStart.Before(windowEnd) && dtStart.After(windowStart) { add(dtStart) }
    }
    return out
}

// helpers
func parseRRule(s string) map[string]string { m:=map[string]string{}; for _,p:= range strings.Split(s, ";") { if p=="" {continue}; kv:=strings.SplitN(p, "=",2); if len(kv)==2 { m[strings.ToUpper(kv[0])] = kv[1] } }; return m }
func atoi(s string, def int) int { if s=="" {return def}; n,err := strconv.Atoi(s); if err!=nil {return def}; return n }
func parseIntList(s string) []int { if s=="" {return nil}; parts:=strings.Split(s,","); out:=make([]int,0,len(parts)); for _,p:=range parts { if n,err:=strconv.Atoi(p); err==nil { out=append(out,n) } }; return out }
func parseList(s string) []string { if s=="" {return nil}; return strings.Split(s,",") }
func parseTime(s string) time.Time { if s=="" {return time.Time{}}; // YYYYMMDD or YYYYMMDDTHHMMSSZ
    if strings.HasSuffix(s, "Z") { t, _ := time.Parse("20060102T150405Z", s); return t }
    t,_ := time.Parse("20060102", s); return t }
func alignDaily(start time.Time, interval int, winStart time.Time) time.Time { if !winStart.After(start) {return start}; diff := int(winStart.Sub(time.Date(start.Year(),start.Month(),start.Day(),0,0,0,0,time.UTC)).Hours()/24); steps := diff/interval; cand := start.AddDate(0,0,steps*interval); if cand.Before(winStart) { cand = cand.AddDate(0,0,interval) }; return cand }
func beforeEnd(t time.Time, until time.Time, count int, produced int) bool { if !until.IsZero() && t.After(until) { return false }; if count>0 && produced>=count { return false }; return true }
func weekStartOf(d time.Time) time.Time { anchor := time.Date(d.Year(), d.Month(), d.Day(), 0,0,0,0, time.UTC); delta := (int(anchor.Weekday()) + 6) % 7; return anchor.AddDate(0,0,-delta) }
func weekdaysOrDefault(byday []string, def time.Weekday) []time.Weekday { if len(byday)==0 { return []time.Weekday{def} }; out:=make([]time.Weekday,0,len(byday)); for _,c:=range byday { out=append(out, codeToWeekday(c)) }; return out }
func codeToWeekday(code string) time.Weekday { switch strings.ToUpper(code){ case "MO":return time.Monday; case "TU":return time.Tuesday; case "WE":return time.Wednesday; case "TH":return time.Thursday; case "FR":return time.Friday; case "SA":return time.Saturday; default: return time.Sunday } }
func parsePositionalByDay(s string) (int, time.Weekday, bool) { if s=="" {return 0,time.Monday,false}; for _,p := range strings.Split(s, ",") { // ex: 1MO or -1SU
        if len(p)>=3 { nstr:=p[:len(p)-2]; if n,err:=strconv.Atoi(nstr); err==nil { return n, codeToWeekday(p[len(p)-2:]), true } }
    }; return 0,time.Monday,false }
func nthWeekdayOfMonth(year int, month int, wd time.Weekday, n int) int { daysInMonth := time.Date(year, time.Month(month)+1, 0, 0,0,0,0,time.UTC).Day(); if n>0 { count:=0; for d:=1; d<=daysInMonth; d++ { if time.Date(year,time.Month(month),d,0,0,0,0,time.UTC).Weekday()==wd { count++; if count==n { return d } } }; return daysInMonth } else { count:=0; for d:=daysInMonth; d>=1; d-- { if time.Date(year,time.Month(month),d,0,0,0,0,time.UTC).Weekday()==wd { count++; if count==-n { return d } } }; return 1 } }
func mustParse(iso string) time.Time { t,_ := time.Parse(time.RFC3339, iso); return t }
func withUntil(e model.Event, until time.Time) string { // naive string update; rebuild RRULE ideally
    rr := "FREQ=DAILY"
    if e.RecurrenceRule!=nil && *e.RecurrenceRule!="" { rr = *e.RecurrenceRule }
    // remove COUNT
    parts := strings.Split(rr, ";"); out:=[]string{}
    for _,p := range parts { if strings.HasPrefix(p, "COUNT=") || strings.HasPrefix(p, "UNTIL=") || p=="" { continue }; out = append(out, p) }
    out = append(out, "UNTIL="+until.UTC().Format("20060102T150405Z"))
    return strings.Join(out, ";")
}
func parseExdates(e model.Event) []time.Time { return []time.Time{} }

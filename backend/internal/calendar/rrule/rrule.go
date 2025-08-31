// Пакет rrule содержит минимальную серверную реализацию базовых правил
// повторения событий (RFC 5545) для нужд MVP. Основные цели:
// - Разворачивать инстансы серии строго в пределах видимого окна
//   [windowStart, windowEnd) — полуинтервал, конец не включается;
// - Поддерживать распространённые комбинации: DAILY/WEEKLY/MONTHLY/YEARLY,
//   INTERVAL, BYDAY, BYMONTHDAY, BYMONTH, COUNT/UNTIL, позиционный BYDAY в
//   MONTHLY (например, 1MO или -1SU);
// - Учитывать EXDATE как список UTC‑дат.
//
// Все вычисления выполняются в UTC, т.к. хранение событий в БД ведётся в UTC.
package rrule

import (
	"strconv"
	"strings"
	"time"
)

// EventSpec описывает базовую серию для экспансии. Это «чистая» модель,
// не привязанная к БД: старт, конец, RRULE и EXDATE. Длительность события
// вычисляется как EndUTC-StartUTC и применяется к каждому инстансу.
type EventSpec struct {
	StartUTC time.Time
	EndUTC   time.Time
	Rule     string
	Exdates  []time.Time
}

// ExpandOccurrences разворачивает серию в пределах окна [windowStart, windowEnd)
// и возвращает список UTC‑дат начала каждого инстанса. Конец инстанса равен
// StartUTC + (spec.EndUTC - spec.StartUTC) и вычисляется вызывающей стороной.
//
// Алгоритм работает по следующей схеме:
// 1) Разбираем RRULE в карту параметров (без строгой валидации).
// 2) В зависимости от FREQ генерируем последовательность кандидатов с шагом
//    INTERVAL, выравнивая первую точку по границе окна для минимизации итераций.
// 3) Для WEEKLY используем понедельник как начало недели, BYDAY задаёт набор
//    будних дней (MO..SU). Для MONTHLY поддерживаем два случая: BYMONTHDAY и
//    позиционный BYDAY (nMO, -1SU). Для YEARLY учитываем BYMONTH/BYMONTHDAY.
// 4) Применяем COUNT/UNTIL и фильтруем по полуинтервалу [start,end), затем
//    исключаем EXDATE.
//
// Важно: функция не занимается раскладкой перекрытий и не строит визуальную
// сетку — только выдаёт точки начала инстансов.
func ExpandOccurrences(spec EventSpec, windowStart, windowEnd time.Time) []time.Time {
	if strings.TrimSpace(spec.Rule) == "" {
		return nil
	}
	rule := parseRRule(spec.Rule)
	freq := strings.ToUpper(rule["FREQ"])
	if freq == "" {
		freq = "DAILY"
	}
	interval := atoi(rule["INTERVAL"], 1)
	until := parseTime(rule["UNTIL"]) // zero если нет
	count := atoi(rule["COUNT"], 0)
	byday := parseList(rule["BYDAY"])              // MO,TU,... или 1MO,-1SU в MONTHLY
	bymonthday := parseIntList(rule["BYMONTHDAY"]) // 1..31
	bymonth := parseIntList(rule["BYMONTH"])       // 1..12

	exset := map[string]struct{}{}
	for _, d := range spec.Exdates {
		exset[d.UTC().Format(time.RFC3339)] = struct{}{}
	}

	dtStart := spec.StartUTC
	add := func(t time.Time, out *[]time.Time) {
		if !t.Before(dtStart) && !t.Before(windowStart) && t.Before(windowEnd) {
			if _, skip := exset[t.Format(time.RFC3339)]; !skip {
				*out = append(*out, t)
			}
		}
	}

	out := []time.Time{}
	switch freq {
	case "DAILY":
		cur := alignDaily(dtStart, interval, windowStart)
		for beforeEnd(cur, until, count, len(out)) && cur.Before(windowEnd) {
			add(cur, &out)
			cur = cur.AddDate(0, 0, interval)
		}
	case "WEEKLY":
		wds := weekdaysOrDefault(byday, dtStart.Weekday())
		weekStart := weekStartOf(windowStart)
		for beforeEnd(weekStart, until, count, len(out)) && weekStart.Before(windowEnd) {
			for _, wd := range wds {
				d := weekStart.AddDate(0, 0, int(wd-1))
				occ := time.Date(d.Year(), d.Month(), d.Day(), dtStart.Hour(), dtStart.Minute(), dtStart.Second(), 0, time.UTC)
				add(occ, &out)
			}
			weekStart = weekStart.AddDate(0, 0, 7*interval)
		}
		sortTimes(out)
		if count > 0 && len(out) > count {
			out = out[:count]
		}
	case "MONTHLY":
		cur := time.Date(windowStart.Year(), windowStart.Month(), 1, dtStart.Hour(), dtStart.Minute(), dtStart.Second(), 0, time.UTC)
		for beforeEnd(cur, until, count, len(out)) && cur.Before(windowEnd) {
			if pos, wd, ok := parsePositionalByDay(rule["BYDAY"]); ok {
				d := nthWeekdayOfMonth(cur.Year(), int(cur.Month()), wd, pos)
				occ := time.Date(cur.Year(), cur.Month(), d, dtStart.Hour(), dtStart.Minute(), dtStart.Second(), 0, time.UTC)
				add(occ, &out)
			} else if len(bymonthday) > 0 {
				for _, md := range bymonthday {
					if md >= 1 && md <= 31 {
						occ := time.Date(cur.Year(), cur.Month(), md, dtStart.Hour(), dtStart.Minute(), dtStart.Second(), 0, time.UTC)
						add(occ, &out)
					}
				}
			} else {
				occ := time.Date(cur.Year(), cur.Month(), dtStart.Day(), dtStart.Hour(), dtStart.Minute(), dtStart.Second(), 0, time.UTC)
				add(occ, &out)
			}
			cur = cur.AddDate(0, interval, 0)
		}
	case "YEARLY":
		// Если BYMONTH задан, идём по конкретным месяцам, иначе — месяц старта.
		months := bymonth
		if len(months) == 0 {
			months = []int{int(dtStart.Month())}
		}
		y := windowStart.Year()
		for {
			for _, m := range months {
				day := dtStart.Day()
				if len(bymonthday) > 0 {
					day = bymonthday[0]
				}
				occ := time.Date(y, time.Month(m), day, dtStart.Hour(), dtStart.Minute(), dtStart.Second(), 0, time.UTC)
				if !beforeEnd(occ, until, count, len(out)) || occ.After(windowEnd) {
					continue
				}
				add(occ, &out)
			}
			if !beforeEnd(time.Date(y, time.January, 1, 0, 0, 0, 0, time.UTC), until, count, len(out)) || time.Date(y+interval, 1, 1, 0, 0, 0, 0, time.UTC).After(windowEnd) {
				if count > 0 && len(out) >= count {
					break
				}
			}
			y += interval
			if y > windowEnd.Year()+5 {
				break
			} // предохранитель
		}
	default:
		if dtStart.Before(windowEnd) && dtStart.After(windowStart) {
			add(dtStart, &out)
		}
	}
	return out
}

// WithUntil возвращает новую строку RRULE с заменой/установкой UNTIL (и
// удалением COUNT). Это удобно для операции «это и все последующие», когда
// исходную серию нужно «обрезать» по моменту split-1сек.
func WithUntil(rule string, until time.Time) string {
	rr := "FREQ=DAILY"
	if strings.TrimSpace(rule) != "" {
		rr = rule
	}
	parts := strings.Split(rr, ";")
	out := []string{}
	for _, p := range parts {
		if strings.HasPrefix(p, "COUNT=") || strings.HasPrefix(p, "UNTIL=") || p == "" {
			continue
		}
		out = append(out, p)
	}
	out = append(out, "UNTIL="+until.UTC().Format("20060102T150405Z"))
	return strings.Join(out, ";")
}

// Helpers — утилиты разбора RRULE и вычислений календарных дат.
func parseRRule(s string) map[string]string {
	m := map[string]string{}
	for _, p := range strings.Split(s, ";") {
		if p == "" {
			continue
		}
		kv := strings.SplitN(p, "=", 2)
		if len(kv) == 2 {
			m[strings.ToUpper(kv[0])] = kv[1]
		}
	}
	return m
}
func atoi(s string, def int) int {
	if s == "" {
		return def
	}
	n, err := strconv.Atoi(s)
	if err != nil {
		return def
	}
	return n
}
func parseIntList(s string) []int {
	if s == "" {
		return nil
	}
	parts := strings.Split(s, ",")
	out := make([]int, 0, len(parts))
	for _, p := range parts {
		if n, err := strconv.Atoi(p); err == nil {
			out = append(out, n)
		}
	}
	return out
}
func parseList(s string) []string {
	if s == "" {
		return nil
	}
	return strings.Split(s, ",")
}
func parseTime(s string) time.Time {
	if s == "" {
		return time.Time{}
	}
	if strings.HasSuffix(s, "Z") {
		t, _ := time.Parse("20060102T150405Z", s)
		return t
	}
	t, _ := time.Parse("20060102", s)
	return t
}
func alignDaily(start time.Time, interval int, winStart time.Time) time.Time {
	if !winStart.After(start) {
		return start
	}
	diff := int(winStart.Sub(time.Date(start.Year(), start.Month(), start.Day(), 0, 0, 0, 0, time.UTC)).Hours() / 24)
	steps := diff / interval
	cand := start.AddDate(0, 0, steps*interval)
	if cand.Before(winStart) {
		cand = cand.AddDate(0, 0, interval)
	}
	return cand
}
func beforeEnd(t time.Time, until time.Time, count int, produced int) bool {
	if !until.IsZero() && t.After(until) {
		return false
	}
	if count > 0 && produced >= count {
		return false
	}
	return true
}
func weekStartOf(d time.Time) time.Time {
	anchor := time.Date(d.Year(), d.Month(), d.Day(), 0, 0, 0, 0, time.UTC)
	delta := (int(anchor.Weekday()) + 6) % 7
	return anchor.AddDate(0, 0, -delta)
}
func weekdaysOrDefault(byday []string, def time.Weekday) []time.Weekday {
	if len(byday) == 0 {
		return []time.Weekday{def}
	}
	out := make([]time.Weekday, 0, len(byday))
	for _, c := range byday {
		out = append(out, codeToWeekday(c))
	}
	return out
}
func codeToWeekday(code string) time.Weekday {
	switch strings.ToUpper(code) {
	case "MO":
		return time.Monday
	case "TU":
		return time.Tuesday
	case "WE":
		return time.Wednesday
	case "TH":
		return time.Thursday
	case "FR":
		return time.Friday
	case "SA":
		return time.Saturday
	default:
		return time.Sunday
	}
}
func parsePositionalByDay(s string) (int, time.Weekday, bool) {
	if s == "" {
		return 0, time.Monday, false
	}
	for _, p := range strings.Split(s, ",") {
		if len(p) >= 3 {
			if n, err := strconv.Atoi(p[:len(p)-2]); err == nil {
				return n, codeToWeekday(p[len(p)-2:]), true
			}
		}
	}
	return 0, time.Monday, false
}
func nthWeekdayOfMonth(year int, month int, wd time.Weekday, n int) int {
	daysInMonth := time.Date(year, time.Month(month)+1, 0, 0, 0, 0, 0, time.UTC).Day()
	if n > 0 {
		count := 0
		for d := 1; d <= daysInMonth; d++ {
			if time.Date(year, time.Month(month), d, 0, 0, 0, 0, time.UTC).Weekday() == wd {
				count++
				if count == n {
					return d
				}
			}
		}
		return daysInMonth
	} else {
		count := 0
		for d := daysInMonth; d >= 1; d-- {
			if time.Date(year, time.Month(month), d, 0, 0, 0, 0, time.UTC).Weekday() == wd {
				count++
				if count == -n {
					return d
				}
			}
		}
		return 1
	}
}
func sortTimes(a []time.Time) {
	for i := 1; i < len(a); i++ {
		j := i
		for j > 0 && a[j].Before(a[j-1]) {
			a[j], a[j-1] = a[j-1], a[j]
			j--
		}
	}
}

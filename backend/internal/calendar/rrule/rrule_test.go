package rrule

import (
    "testing"
    "time"
    "github.com/stretchr/testify/require"
)

func TestExpand_Daily_WindowEdges(t *testing.T) {
    start := time.Date(2025,9,1,9,0,0,0,time.UTC)
    spec := EventSpec{StartUTC:start, EndUTC:start.Add(time.Hour), Rule:"FREQ=DAILY;COUNT=3"}
    // окно начинается ровно на первом инстансе
    occ := ExpandOccurrences(spec, start, start.AddDate(0,0,5))
    require.Len(t, occ, 3)
}

func TestMonthly_Positional_LastSunday(t *testing.T) {
    // Старт внутри месяца; правило: последний воскресенье каждого месяца
    start := time.Date(2025,1,1,9,0,0,0,time.UTC)
    spec := EventSpec{StartUTC:start, EndUTC:start.Add(time.Hour), Rule:"FREQ=MONTHLY;BYDAY=-1SU;COUNT=3"}
    occ := ExpandOccurrences(spec, start, start.AddDate(0,3,0))
    require.Len(t, occ, 3)
    for _,o := range occ { require.Equal(t, time.Sunday, o.Weekday()) }
}

func TestWithUntil_RemovesCount(t *testing.T) {
    r := "FREQ=DAILY;COUNT=10"
    until := time.Date(2025,9,10,23,59,59,0,time.UTC)
    out := WithUntil(r, until)
    require.NotContains(t, out, "COUNT=")
    require.Contains(t, out, "UNTIL=")
}


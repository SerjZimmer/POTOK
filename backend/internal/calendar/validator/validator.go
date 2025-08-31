package validator

import (
    "errors"
    "time"
)

func ValidateTimeRange(start, end time.Time) error {
    if end.Before(start) { return errors.New("end before start") }
    return nil
}


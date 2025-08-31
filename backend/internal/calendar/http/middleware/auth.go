package middleware

import (
    "net/http"
    "strings"
)

// Auth is an optional Bearer auth placeholder. If token present but invalid, respond 401.
func Auth(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        auth := r.Header.Get("Authorization")
        if auth == "" {
            next.ServeHTTP(w, r)
            return
        }
        if !strings.HasPrefix(auth, "Bearer ") || len(auth) <= 7 {
            w.WriteHeader(http.StatusUnauthorized)
            _, _ = w.Write([]byte(`{"code":"unauthorized","message":"Invalid Authorization header"}`))
            return
        }
        // TODO: validate token
        next.ServeHTTP(w, r)
    })
}


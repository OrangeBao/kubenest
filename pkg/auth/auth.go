package auth

import (
	"bytes"
	"crypto/sha256"
	"encoding/base64"
	"net/http"
	"strings"
)

func NewAuthHandler(next http.Handler, user, password string) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/healthz" || r.URL.Path == "/readyz" {
			next.ServeHTTP(w, r)
			return
		}

		auth := r.Header.Get("Authorization")
		if auth == "" {
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}

		userPassBase64 := strings.TrimPrefix(auth, "Basic ")
		userPassBytes, err := base64.StdEncoding.DecodeString(userPassBase64)
		if err != nil {
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}

		userPass := strings.SplitN(string(userPassBytes), ":", 2)
		if len(userPass) != 2 {
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}

		passwordHash := sha256.Sum256([]byte(password))
		userHash := sha256.Sum256([]byte(userPass[1]))
		if userPass[0] != user || !bytes.Equal(userHash[:], passwordHash[:]) {
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}

		next.ServeHTTP(w, r)
	})
}

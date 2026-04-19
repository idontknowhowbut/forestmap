package main

import (
	"context"
	"github.com/jmoiron/sqlx"
    _ "github.com/lib/pq"
	"log"
	"net/http"
	"os"
	"time"

	"forestmap/backend/internal/httpapi"
	"forestmap/backend/internal/store"
)

func main() {
	addr := env("ADDR", ":8080")
	dbURL := os.Getenv("DATABASE_URL")

	if dbURL == "" {
		log.Fatal("DATABASE_URL is not set")
	}

	db, err := sqlx.Open("postgres", dbURL)
	if err != nil {
		log.Fatalf("failed to open db: %v", err)
	}
	defer db.Close()

	if err := db.Ping(); err != nil {
		log.Fatalf("failed to ping db: %v", err)
	}
	log.Println("connected to postgres")

	st := store.NewStore(db)
	handler := httpapi.NewDroneHandler(st)

	auth, err := httpapi.NewJWTAuth(
		context.Background(),
		os.Getenv("OIDC_ISSUER"),
		os.Getenv("OIDC_JWKS_URL"),
	)
	if err != nil {
		log.Fatalf("failed to init jwt auth: %v", err)
	}

	mux := http.NewServeMux()

	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("ok"))
	})

	mux.HandleFunc("/v1/telemetry", auth.RequireRealmRole("drone", handler.HandleTelemetry))
	mux.HandleFunc("/v1/detections", auth.RequireRealmRole("drone", handler.HandleDetections))
	mux.HandleFunc("/v1/detections:query", auth.RequireAnyRealmRole([]string{"viewer", "drone"}, handler.HandleDetectionsQuery))

	log.Printf("listening on %s", addr)
	if err := http.ListenAndServe(addr, logRequests(mux)); err != nil {
		log.Fatal(err)
	}
}

func env(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func logRequests(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		log.Printf("%s %s %s", r.RemoteAddr, r.Method, r.URL.Path)
		next.ServeHTTP(w, r)
		log.Printf("completed in %v", time.Since(start))
	})
}

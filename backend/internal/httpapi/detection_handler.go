package httpapi

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strings"

	"forestmap/backend/internal/model"
	"forestmap/backend/internal/store"
)

type DetectionHandler struct {
	Store *store.Store
}

func NewDetectionHandler(s *store.Store) *DetectionHandler {
	return &DetectionHandler{Store: s}
}

func (h *DetectionHandler) resolveCompanyIDFromClaims(r *http.Request) (string, bool) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		return "", false
	}

	_, company, err := h.Store.EnsureUserAndCompanyByKeycloakUser(
		r.Context(),
		claims.Subject,
		claims.Email,
		claims.FullName,
		claims.RealmAccess.Roles,
	)
	if err != nil {
		return "", false
	}

	return company.ID.String(), true
}

func (h *DetectionHandler) HandleSearchDetections(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeError(w, http.StatusMethodNotAllowed, "METHOD_NOT_ALLOWED", "Method not allowed")
		return
	}

	var req model.DetectionSearchRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "BAD_REQUEST", "Invalid JSON")
		return
	}

	companyID, ok := h.resolveCompanyIDFromClaims(r)
	if !ok {
		writeError(w, http.StatusUnauthorized, "UNAUTHORIZED", "Authentication required")
		return
	}

	results, err := h.Store.SearchDetections(r.Context(), companyID, req)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Internal server error")
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"data": results,
	})
}

func (h *DetectionHandler) HandleGetDetection(w http.ResponseWriter, r *http.Request, id string) {
	companyID, ok := h.resolveCompanyIDFromClaims(r)
	if !ok {
		writeError(w, http.StatusUnauthorized, "UNAUTHORIZED", "Authentication required")
		return
	}

	detection, err := h.Store.GetDetectionByID(r.Context(), id, companyID)
	if err == store.ErrNotFound {
		writeError(w, http.StatusNotFound, "NOT_FOUND", "Detection not found")
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Internal server error")
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"data": detection,
	})
}

func (h *DetectionHandler) HandleGetComments(w http.ResponseWriter, r *http.Request, id string) {
	companyID, ok := h.resolveCompanyIDFromClaims(r)
	if !ok {
		writeError(w, http.StatusUnauthorized, "UNAUTHORIZED", "Authentication required")
		return
	}

	comments, err := h.Store.GetDetectionComments(r.Context(), id, companyID)
	if err == store.ErrNotFound {
		writeError(w, http.StatusNotFound, "NOT_FOUND", "Detection not found")
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Internal server error")
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"data": comments,
	})
}

func (h *DetectionHandler) HandleCreateComment(w http.ResponseWriter, r *http.Request, id string) {
	fmt.Printf("DEBUG HandleCreateComment id=%q\n", id)

	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, "UNAUTHORIZED", "Authentication required")
		return
	}

	companyID, ok := h.resolveCompanyIDFromClaims(r)
	if !ok {
		writeError(w, http.StatusUnauthorized, "UNAUTHORIZED", "Authentication required")
		return
	}

	var req struct {
		Body string `json:"body"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || strings.TrimSpace(req.Body) == "" {
		writeError(w, http.StatusBadRequest, "BAD_REQUEST", "body is required")
		return
	}

	comment, err := h.Store.CreateDetectionComment(r.Context(), id, companyID, claims.Subject, req.Body)
	if err == store.ErrNotFound {
		writeError(w, http.StatusNotFound, "NOT_FOUND", "Detection not found")
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Internal server error")
		return
	}

	writeJSON(w, http.StatusCreated, map[string]any{
		"data": comment,
	})
}

func (h *DetectionHandler) HandleDetectionRoutes(w http.ResponseWriter, r *http.Request) {
	path := strings.TrimPrefix(r.URL.Path, "/v1/detections/")
	parts := strings.Split(path, "/")
	fmt.Printf("DEBUG HandleDetectionRoutes path=%q parts=%v method=%q\n", path, parts, r.Method)

	if len(parts) == 0 || strings.TrimSpace(parts[0]) == "" {
		writeError(w, http.StatusNotFound, "NOT_FOUND", "Not found")
		return
	}

	id := parts[0]

	if len(parts) == 1 && r.Method == http.MethodGet {
		h.HandleGetDetection(w, r, id)
		return
	}

	if len(parts) == 2 && parts[1] == "comments" && r.Method == http.MethodGet {
		h.HandleGetComments(w, r, id)
		return
	}

	if len(parts) == 2 && parts[1] == "comments" && r.Method == http.MethodPost {
		h.HandleCreateComment(w, r, id)
		return
	}

	writeError(w, http.StatusNotFound, "NOT_FOUND", "Not found")
}

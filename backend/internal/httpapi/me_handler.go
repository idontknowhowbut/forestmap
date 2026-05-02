package httpapi

import (
	"encoding/json"
	"net/http"
)

// GET /me
// Контракт: MeResponse { data: Me }
func (h *DetectionHandler) HandleMe(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeError(w, http.StatusMethodNotAllowed, "METHOD_NOT_ALLOWED", "Method not allowed")
		return
	}

	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, "UNAUTHORIZED", "Authentication required")
		return
	}

	company, err := h.Store.GetCompanyByID(r.Context(), claims.CompanyID)
	if err != nil {
		writeError(w, http.StatusUnauthorized, "UNAUTHORIZED", "Authentication required")
		return
	}

	resp := map[string]any{
		"data": map[string]any{
			"id":             claims.Subject,
			"keycloakUserId": claims.Subject,
			"email":          claims.Email,
			"fullName":       claims.FullName,
			"company": map[string]any{
				"id":   company.ID,
				"name": company.Name,
			},
		},
	}

	writeJSON(w, http.StatusOK, resp)
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func writeError(w http.ResponseWriter, status int, code, message string) {
	writeJSON(w, status, map[string]any{
		"error": map[string]any{
			"code":    code,
			"message": message,
		},
	})
}

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

	externalUserID := claims.ExternalUserID()
	user, company, err := h.Store.EnsureUserAndCompanyByKeycloakUser(
		r.Context(),
		externalUserID,
		claims.Email,
		claims.FullName,
		claims.RealmAccess.Roles,
	)
	if err != nil {
		writeError(w, http.StatusUnauthorized, "UNAUTHORIZED", "Authentication required")
		return
	}

	resp := map[string]any{
		"data": map[string]any{
			"id":             user.ID,
			"keycloakUserId": externalUserID,
			"email":          user.Email,
			"fullName":       user.FullName,
			"roles":          claims.RealmAccess.Roles,
			"company": map[string]any{
				"id":   company.ID,
				"name": company.Name,
				"code": company.Code,
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

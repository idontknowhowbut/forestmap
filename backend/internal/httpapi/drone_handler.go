package httpapi

import (
	"bytes"
	"encoding/json"
	"fmt"
	"forestmap/backend/internal/model"
	"forestmap/backend/internal/store"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"unicode"

	"github.com/google/uuid"
)

type DroneHandler struct {
	Store *store.Store
}

func NewDroneHandler(s *store.Store) *DroneHandler {
	return &DroneHandler{Store: s}
}

func (h *DroneHandler) resolveCompanyIDFromClaims(r *http.Request) (string, bool) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		return "", false
	}

	_, company, err := h.Store.EnsureUserAndCompanyByKeycloakUser(
		r.Context(),
		claims.ExternalUserID(),
		claims.Email,
		claims.FullName,
		claims.RealmAccess.Roles,
	)
	if err != nil {
		return "", false
	}

	return company.ID.String(), true
}

func (h *DroneHandler) HandleTelemetry(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	companyID, ok := h.resolveCompanyIDFromClaims(r)
	if !ok {
		http.Error(w, "authentication required", http.StatusUnauthorized)
		return
	}

	var req model.TelemetryRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid JSON", http.StatusBadRequest)
		return
	}

	if err := h.Store.SaveTelemetry(req, companyID); err != nil {
		fmt.Printf("ERROR SaveTelemetry: %v\n", err)
		http.Error(w, "Internal Server Error", http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusCreated)
}

func validateDetectionBatch(batch model.DetectionBatchRequest) error {
	if strings.TrimSpace(batch.FlightID) == "" {
		return fmt.Errorf("flight_id is required")
	}
	if strings.TrimSpace(batch.TelemetryPacketID) == "" {
		return fmt.Errorf("telemetry_packet_id is required")
	}
	if batch.DetectedAt.IsZero() {
		return fmt.Errorf("detected_at is required")
	}
	if len(batch.Objects) == 0 {
		return fmt.Errorf("objects must not be empty")
	}

	for i, obj := range batch.Objects {
		if strings.TrimSpace(obj.Class) == "" {
			return fmt.Errorf("objects[%d].class is required", i)
		}
		if obj.Score < 0 || obj.Score > 1 {
			return fmt.Errorf("objects[%d].score must be in range 0..1", i)
		}
		if obj.Severity < 0 || obj.Severity > 100 {
			return fmt.Errorf("objects[%d].severity must be in range 0..100", i)
		}
		if strings.TrimSpace(obj.GeometryGeo.Type) == "" || len(obj.GeometryGeo.Coordinates) == 0 {
			return fmt.Errorf("objects[%d].geometry_geo is required", i)
		}
	}

	return nil
}

func sanitizeFilenamePart(value string) string {
	var b strings.Builder
	for _, r := range value {
		switch {
		case unicode.IsLetter(r), unicode.IsDigit(r):
			b.WriteRune(r)
		case r == '-', r == '_', r == '.':
			b.WriteRune(r)
		default:
			b.WriteRune('_')
		}
	}
	return b.String()
}

func safeUploadFilename(original string) string {
	base := filepath.Base(strings.TrimSpace(original))
	ext := sanitizeFilenamePart(filepath.Ext(base))
	name := strings.TrimSuffix(base, filepath.Ext(base))
	if name == "" {
		name = "image"
	}

	var b strings.Builder
	for _, r := range name {
		switch {
		case unicode.IsLetter(r), unicode.IsDigit(r):
			b.WriteRune(r)
		case r == '-', r == '_', r == '.':
			b.WriteRune(r)
		default:
			b.WriteRune('_')
		}
	}

	safeName := strings.Trim(b.String(), "._-")
	if safeName == "" {
		safeName = "image"
	}

	return fmt.Sprintf("%s_%s%s", uuid.NewString(), safeName, ext)
}

func (h *DroneHandler) HandleDetections(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	companyID, ok := h.resolveCompanyIDFromClaims(r)
	if !ok {
		http.Error(w, "authentication required", http.StatusUnauthorized)
		return
	}

	if err := r.ParseMultipartForm(10 << 20); err != nil {
		http.Error(w, "File too large", http.StatusBadRequest)
		return
	}

	jsonStr := r.FormValue("data")
	if jsonStr == "" {
		http.Error(w, "Missing data json", http.StatusBadRequest)
		return
	}

	var batch model.DetectionBatchRequest
	if err := json.Unmarshal([]byte(jsonStr), &batch); err != nil {
		http.Error(w, "Invalid JSON data", http.StatusBadRequest)
		return
	}

	if err := validateDetectionBatch(batch); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	file, header, err := r.FormFile("image")
	if err != nil {
		http.Error(w, "Missing image", http.StatusBadRequest)
		return
	}
	defer file.Close()

	uploadDir := os.Getenv("UPLOAD_DIR")
	if uploadDir == "" {
		uploadDir = "/uploads"
	}
	if err := os.MkdirAll(uploadDir, 0755); err != nil {
		http.Error(w, "Upload directory error", http.StatusInternalServerError)
		return
	}

	filename := safeUploadFilename(header.Filename)
	fsPath := filepath.Join(uploadDir, filename)
	urlPath := "/uploads/" + filename

	dst, err := os.OpenFile(fsPath, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0644)
	if err != nil {
		http.Error(w, "File save error", http.StatusInternalServerError)
		return
	}

	if _, err := io.Copy(dst, file); err != nil {
		dst.Close()
		os.Remove(fsPath)
		http.Error(w, "File write error", http.StatusInternalServerError)
		return
	}
	if err := dst.Close(); err != nil {
		os.Remove(fsPath)
		http.Error(w, "File close error", http.StatusInternalServerError)
		return
	}

	if err := h.Store.SaveDetections(batch, urlPath, companyID); err != nil {
		os.Remove(fsPath)
		fmt.Printf("ERROR saving detections: %v\n", err)

		http.Error(w, "Database error", http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusCreated)
	fmt.Fprintf(w, `{"status":"saved", "count":%d}`, len(batch.Objects))
}

// HandleDetectionsQuery returns detections as GeoJSON FeatureCollection.
// POST /api/v1/detections:query  (application/json)
func (h *DroneHandler) HandleDetectionsQuery(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	companyID, ok := h.resolveCompanyIDFromClaims(r)
	if !ok {
		http.Error(w, "authentication required", http.StatusUnauthorized)
		return
	}

	body, err := io.ReadAll(io.LimitReader(r.Body, 2<<20))
	if err != nil {
		http.Error(w, "Bad request", http.StatusBadRequest)
		return
	}
	if len(bytes.TrimSpace(body)) == 0 {
		http.Error(w, "Empty body", http.StatusBadRequest)
		return
	}

	var req model.DetectionsQueryRequest
	if err := json.Unmarshal(body, &req); err != nil {
		http.Error(w, "Invalid JSON", http.StatusBadRequest)
		return
	}

	if req.Geom != "" && req.Geom != "auto" && req.Geom != "point" && req.Geom != "polygon" {
		http.Error(w, "Invalid geom (auto|point|polygon)", http.StatusBadRequest)
		return
	}

	if len(req.BBox) > 0 && len(req.BBox) != 4 {
		http.Error(w, "Invalid bbox (need 4 numbers)", http.StatusBadRequest)
		return
	}

	if len(req.AOI) > 0 && !json.Valid(req.AOI) {
		http.Error(w, "Invalid aoi (must be valid GeoJSON geometry)", http.StatusBadRequest)
		return
	}
	out, err := h.Store.QueryDetectionsGeoJSON(r.Context(), req, companyID)
	if err != nil {
		fmt.Printf("ERROR QueryDetectionsGeoJSON: %v\n", err)
		http.Error(w, "Internal Server Error", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/geo+json; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(out)
}

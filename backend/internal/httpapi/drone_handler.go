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
	"time"
)

type DroneHandler struct {
	Store *store.Store
}

func NewDroneHandler(s *store.Store) *DroneHandler {
	return &DroneHandler{Store: s}
}

func (h *DroneHandler) HandleTelemetry(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	companyID, ok := CompanyIDFromContext(r.Context())
    if !ok {
        http.Error(w, "missing company_id in token", http.StatusUnauthorized)
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

func (h *DroneHandler) HandleDetections(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	companyID, ok := CompanyIDFromContext(r.Context())
    if !ok {
        http.Error(w, "missing company_id in token", http.StatusUnauthorized)
        return
    }

	if err := r.ParseMultipartForm(10 << 20); err != nil {
		http.Error(w, "File too large", http.StatusBadRequest)
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
	_ = os.MkdirAll(uploadDir, 0755)

	filename := fmt.Sprintf("%d_%s", time.Now().Unix(), header.Filename)
	fsPath := filepath.Join(uploadDir, filename)
	urlPath := "/uploads/" + filename

	dst, err := os.Create(fsPath)
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
	dst.Close()

	jsonStr := r.FormValue("data")
	if jsonStr == "" {
		os.Remove(fsPath)
		http.Error(w, "Missing data json", http.StatusBadRequest)
		return
	}

	var batch model.DetectionBatchRequest
	if err := json.Unmarshal([]byte(jsonStr), &batch); err != nil {
		os.Remove(fsPath)
		http.Error(w, "Invalid JSON data", http.StatusBadRequest)
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
	out, err := h.Store.QueryDetectionsGeoJSON(r.Context(), req)
	if err != nil {
		fmt.Printf("ERROR QueryDetectionsGeoJSON: %v\n", err)
		http.Error(w, "Internal Server Error", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/geo+json; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(out)
}

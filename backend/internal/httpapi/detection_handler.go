package httpapi

import "forestmap/backend/internal/store"

type DetectionHandler struct {
	Store *store.Store
}

func NewDetectionHandler(s *store.Store) *DetectionHandler {
	return &DetectionHandler{Store: s}
}

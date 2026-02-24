package model

import (
	"encoding/json"
	"time"
)

type TelemetryRequest struct {
	FlightID   string         `json:"flight_id"`
	PacketID   string         `json:"packet_id"`
	DroneID    string         `json:"drone_id"`
	RecordedAt time.Time      `json:"recorded_at"`
	Location   GeoLocation    `json:"location"`
	Camera     CameraSettings `json:"camera"`
	Speed      float64        `json:"speed"`
	Battery    int            `json:"battery"`
}

type GeoLocation struct {
	Lat float64 `json:"lat"`
	Lon float64 `json:"lon"`
	Alt float64 `json:"alt"`
}

type CameraSettings struct {
	Heading float64 `json:"heading"`
	Pitch   float64 `json:"pitch"`
	FOV     float64 `json:"fov"`
}

type DetectionBatchRequest struct {
	FlightID          string            `json:"flight_id"`
	TelemetryPacketID string            `json:"telemetry_packet_id"`
	DetectedAt        time.Time         `json:"detected_at"`
	Objects           []DetectionObject `json:"objects"`
}

type DetectionObject struct {
	Class         string         `json:"class"`
	Score         float64        `json:"score"`
	Severity      float64        `json:"severity"`
	GeometryGeo   GeoJSONPolygon `json:"geometry_geo"`
	GeometryImage Box            `json:"geometry_image"`
}

type Box struct {
	X float64 `json:"x"`
	Y float64 `json:"y"`
	W float64 `json:"w"`
	H float64 `json:"h"`
}

type GeoJSONPolygon struct {
	Type        string        `json:"type"`
	Coordinates [][][]float64 `json:"coordinates"`
}

type DetectionsQueryRequest struct {
	Classes  []string `json:"classes,omitempty"` 
	Geom     string   `json:"geom,omitempty"`    
	BBox     []float64 `json:"bbox,omitempty"`   
	AOI      json.RawMessage `json:"aoi,omitempty"`
	MinScore *float64 `json:"min_score,omitempty"`
	FlightID string   `json:"flight_id,omitempty"`
	Since    *time.Time `json:"since,omitempty"`
	Limit    int      `json:"limit,omitempty"`
}

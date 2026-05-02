package store

import (
	"forestmap/backend/internal/model"
	"github.com/jmoiron/sqlx"
	"encoding/json"
	"fmt"
  "context"
	"strconv"
	"strings"
	"github.com/lib/pq"
	
)

type Store struct {
	db *sqlx.DB
}

func NewStore(db *sqlx.DB) *Store {
	return &Store{db: db}
}

func (s *Store) SaveTelemetry(t model.TelemetryRequest, companyID string) error {
	query := `
		INSERT INTO telemetry (
			packet_id, flight_id, drone_id, company_id, recorded_at, 
			location, 
			heading, pitch, fov, speed, battery
		) VALUES (
			$1, $2, $3, $4, $5,
			ST_SetSRID(ST_MakePoint($6, $7, $8), 4326),
			$9, $10, $11, $12, $13
		)
	`

	_, err := s.db.Exec(query,
		t.PacketID, t.FlightID, t.DroneID, companyID, t.RecordedAt,
		t.Location.Lon, t.Location.Lat, t.Location.Alt,
		t.Camera.Heading, t.Camera.Pitch, t.Camera.FOV,
		t.Speed, t.Battery,
	)

	if err != nil {
		return fmt.Errorf("failed to insert telemetry: %w", err)
	}
	return nil
}

func (s *Store) SaveDetections(batch model.DetectionBatchRequest, imagePath string, companyID string) error {
	tx, err := s.db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	query := `
		INSERT INTO detections (
			company_id, flight_id, telemetry_packet_id, detected_at,
			class_type, score, severity,
			geometry_geo, geometry_image, image_path
		) VALUES (
			$1, $2, $3, $4, 
			$5, $6, $7,
			ST_SetSRID(ST_GeomFromGeoJSON($8), 4326), 
			$9, $10
		)
	`

	for _, obj := range batch.Objects {
		geoBytes, err := json.Marshal(obj.GeometryGeo)
		if err != nil {
			continue
		}

		boxBytes, err := json.Marshal(obj.GeometryImage)
		if err != nil {
			continue
		}

		_, err = tx.Exec(query,
			companyID, batch.FlightID, batch.TelemetryPacketID, batch.DetectedAt,
			obj.Class, obj.Score, obj.Severity,
			string(geoBytes),
			boxBytes,
			imagePath,
		)

		if err != nil {
			return fmt.Errorf("insert failed: %w", err)
		}
	}

	return tx.Commit()
}

func (s *Store) QueryDetectionsGeoJSON(ctx context.Context, req model.DetectionsQueryRequest, companyID string) ([]byte, error) {
	geomMode := req.Geom
	if geomMode == "" {
		geomMode = "auto"
	}

	limit := req.Limit
	if limit <= 0 || limit > 5000 {
		limit = 2000
	}

	args := []any{geomMode, companyID}
	n := 3

	where := []string{
		"d.geometry_geo IS NOT NULL",
		"d.company_id = $2",
	}

	if len(req.Classes) > 0 {
		where = append(where, "d.class_type = ANY($"+strconv.Itoa(n)+")")
		args = append(args, pq.Array(req.Classes))
		n++
	}

	if req.FlightID != "" {
		where = append(where, "d.flight_id = $"+strconv.Itoa(n))
		args = append(args, req.FlightID)
		n++
	}

	if req.MinScore != nil {
		where = append(where, "d.score >= $"+strconv.Itoa(n))
		args = append(args, *req.MinScore)
		n++
	}

	if req.Since != nil {
		where = append(where, "d.detected_at >= $"+strconv.Itoa(n))
		args = append(args, *req.Since)
		n++
	}

	if len(req.BBox) > 0 {
		where = append(where,
			"ST_Intersects(d.geometry_geo, ST_MakeEnvelope($"+strconv.Itoa(n)+",$"+strconv.Itoa(n+1)+",$"+strconv.Itoa(n+2)+",$"+strconv.Itoa(n+3)+",4326))",
		)
		args = append(args, req.BBox[0], req.BBox[1], req.BBox[2], req.BBox[3])
		n += 4
	}

	if len(req.AOI) > 0 {
		where = append(where,
			"ST_Intersects(d.geometry_geo, ST_SetSRID(ST_GeomFromGeoJSON($"+strconv.Itoa(n)+"), 4326))",
		)
		args = append(args, string(req.AOI))
		n++
	}

	limitParam := "$" + strconv.Itoa(n)
	args = append(args, limit)

	q := `
WITH features AS (
  SELECT jsonb_build_object(
    'type','Feature',
    'id', d.id,
    'geometry', (
      CASE
        WHEN $1 = 'polygon' THEN ST_AsGeoJSON(d.geometry_geo)::jsonb
        WHEN $1 = 'point'   THEN ST_AsGeoJSON(ST_PointOnSurface(d.geometry_geo))::jsonb
        ELSE (
          CASE
            WHEN d.class_type = 'fire' THEN ST_AsGeoJSON(ST_PointOnSurface(d.geometry_geo))::jsonb
            ELSE ST_AsGeoJSON(d.geometry_geo)::jsonb
          END
        )
      END
    ),
    'properties', jsonb_build_object(
      'flight_id', d.flight_id,
      'detected_at', d.detected_at,
      'class_type', d.class_type,
      'score', d.score,
      'severity', d.severity,
      'image_path', d.image_path,
      'geometry_image', d.geometry_image,
      'telemetry_packet_id', d.telemetry_packet_id
    )
  ) AS feature
  FROM detections d
  WHERE ` + strings.Join(where, " AND ") + `
  ORDER BY d.detected_at DESC
  LIMIT ` + limitParam + `
  )
  SELECT jsonb_build_object(
    'type','FeatureCollection',
    'features', COALESCE(jsonb_agg(features.feature), '[]'::jsonb)
  )::jsonb
  FROM features;
`


	var out []byte
	if err := s.db.QueryRowContext(ctx, q, args...).Scan(&out); err != nil {
		return nil, fmt.Errorf("failed to query detections geojson: %w", err)
	}
	return out, nil
}

package model

import (
	"time"

	"github.com/google/uuid"
)

type Company struct {
	ID        uuid.UUID `db:"id"`
	Name      string    `db:"name"`
	Code      string    `db:"code"`
	Status    string    `db:"status"`
	CreatedAt time.Time `db:"created_at"`
	UpdatedAt time.Time `db:"updated_at"`
}

type User struct {
	ID             uuid.UUID `db:"id"`
	KeycloakUserID string    `db:"keycloak_user_id"`
	Email          string    `db:"email"`
	FullName       string    `db:"full_name"`
	Status         string    `db:"status"`
	CreatedAt      time.Time `db:"created_at"`
	UpdatedAt      time.Time `db:"updated_at"`
}

type CompanyUser struct {
	ID        uuid.UUID `db:"id"`
	CompanyID uuid.UUID `db:"company_id"`
	UserID    uuid.UUID `db:"user_id"`
	Role      string    `db:"role"`
	Status    string    `db:"status"`
	JoinedAt  time.Time `db:"joined_at"`
	CreatedAt time.Time `db:"created_at"`
	UpdatedAt time.Time `db:"updated_at"`
}

type Flight struct {
	ID               uuid.UUID  `db:"id"`
	CompanyID        uuid.UUID  `db:"company_id"`
	ExternalID       string     `db:"external_id"`
	Status           string     `db:"status"`
	FlightStartedAt  time.Time  `db:"flight_started_at"`
	FlightFinishedAt *time.Time `db:"flight_finished_at"`
	CreatedAt        time.Time  `db:"created_at"`
	UpdatedAt        time.Time  `db:"updated_at"`
}

type Detections struct {
	ID                uuid.UUID  `db:"id"`
	CompanyID         uuid.UUID  `db:"company_id"`
	TelemetryPacketID *uuid.UUID `db:"telemetry_packet_id"`
	FlightID          string     `db:"flight_id"`
	DetectedAt        time.Time  `db:"detected_at"`
	ClassType         string     `db:"class_type"`
	Score             *float64   `db:"score"`
	Severity          *int       `db:"severity"`
	ImagePath         *string    `db:"image_path"`
}

type Telemetry struct {
	PacketID   uuid.UUID `db:"packet_id"`
	CompanyID  uuid.UUID `db:"company_id"`
	FlightID   string    `db:"flight_id"`
	DroneID    string    `db:"drone_id"`
	RecordedAt time.Time `db:"recorded_at"`
	Heading    *float64  `db:"heading"`
	Pitch      *float64  `db:"pitch"`
	FOV        *float64  `db:"fov"`
	Speed      *float64  `db:"speed"`
	Battery    *int      `db:"battery"`
}

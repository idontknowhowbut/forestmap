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

type Detection struct {
	ID              uuid.UUID  `db:"id"`
	FlightID        uuid.UUID  `db:"flight_id"`
	Type            string     `db:"type"`
	Status          string     `db:"status"`
	Score           *int       `db:"score"`
	Title           string     `db:"title"`
	Description     string     `db:"description"`
	Geometry        *string    `db:"geometry"` // WKT или WKB, зависит от драйвера
	CentroidLat     *float64   `db:"centroid_lat"`
	CentroidLon     *float64   `db:"centroid_lon"`
	Area            *float64   `db:"area"`
	LastDetectionAt time.Time  `db:"last_detection_at"`
	CreatedBy       *uuid.UUID `db:"created_by"`
	UpdatedBy       *uuid.UUID `db:"updated_by"`
	CreatedAt       time.Time  `db:"created_at"`
	UpdatedAt       time.Time  `db:"updated_at"`
	ArchivedAt      *time.Time `db:"archived_at"`
}

type DetectionEvent struct {
	ID          uuid.UUID  `db:"id"`
	DetectionID uuid.UUID  `db:"detection_id"`
	EventType   string     `db:"event_type"`
	Severity    *int       `db:"severity"`
	Payload     *string    `db:"payload"` // JSON as string
	CreatedBy   *uuid.UUID `db:"created_by"`
	EventAt     time.Time  `db:"event_at"`
	CreatedAt   time.Time  `db:"created_at"`
}

type DetectionComment struct {
	ID           uuid.UUID  `db:"id"`
	DetectionID  uuid.UUID  `db:"detection_id"`
	AuthorUserID uuid.UUID  `db:"author_user_id"`
	Body         string     `db:"body"`
	CreatedAt    time.Time  `db:"created_at"`
	UpdatedAt    time.Time  `db:"updated_at"`
	DeletedAt    *time.Time `db:"deleted_at"`
}

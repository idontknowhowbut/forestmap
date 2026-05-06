package store

import (
	"context"
	"database/sql"
	"fmt"
	"strings"

	"forestmap/backend/internal/model"

	"github.com/google/uuid"
)

// GetCompanyByID возвращает компанию по id.
func (s *Store) GetCompanyByID(ctx context.Context, id string) (*model.Company, error) {
	var c model.Company
	err := s.db.GetContext(ctx, &c, `
		SELECT id, name, code, status, created_at, updated_at
		FROM companies
		WHERE id = $1
	`, id)
	if err != nil {
		return nil, fmt.Errorf("company not found: %w", err)
	}
	return &c, nil
}

func primaryRoleFromRoles(roles []string) string {
	for _, role := range roles {
		if role == "admin" {
			return "admin"
		}
	}
	for _, role := range roles {
		if role == "drone" {
			return "drone"
		}
	}
	return "viewer"
}

func (s *Store) EnsureUserAndCompanyByKeycloakUser(
	ctx context.Context,
	keycloakUserID string,
	email string,
	fullName string,
	roles []string,
) (*model.User, *model.Company, error) {
	tx, err := s.db.BeginTxx(ctx, nil)
	if err != nil {
		return nil, nil, fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback()

	var user model.User
	err = tx.GetContext(ctx, &user, `
		SELECT id, keycloak_user_id, email, full_name, status, created_at, updated_at
		FROM users
		WHERE keycloak_user_id = $1
	`, keycloakUserID)

	if err != nil {
		if err != sql.ErrNoRows {
			return nil, nil, fmt.Errorf("get user by keycloak id: %w", err)
		}

		if strings.TrimSpace(email) == "" {
			email = fmt.Sprintf("%s@local", keycloakUserID)
		}
		if strings.TrimSpace(fullName) == "" {
			fullName = email
		}

		userID := uuid.New()

		err = tx.GetContext(ctx, &user, `
			INSERT INTO users (
				id, keycloak_user_id, email, full_name, status, created_at, updated_at
			) VALUES (
				$1, $2, $3, $4, 'active', now(), now()
			)
			RETURNING id, keycloak_user_id, email, full_name, status, created_at, updated_at
		`, userID, keycloakUserID, email, fullName)
		if err != nil {
			return nil, nil, fmt.Errorf("insert user: %w", err)
		}
	} else {
		// Поддерживаем профиль в актуальном состоянии
		_, err = tx.ExecContext(ctx, `
			UPDATE users
			SET email = $2,
			    full_name = $3,
			    updated_at = now()
			WHERE id = $1
		`, user.ID, email, fullName)
		if err != nil {
			return nil, nil, fmt.Errorf("update user profile: %w", err)
		}
	}

	var company model.Company
	err = tx.GetContext(ctx, &company, `
		SELECT c.id, c.name, c.code, c.status, c.created_at, c.updated_at
		FROM companies c
		JOIN company_users cu ON cu.company_id = c.id
		WHERE cu.user_id = $1
		  AND cu.status = 'active'
		  AND c.status = 'active'
		ORDER BY cu.created_at ASC
		LIMIT 1
	`, user.ID)

	if err == nil {
		if err := tx.Commit(); err != nil {
			return nil, nil, fmt.Errorf("commit tx: %w", err)
		}
		return &user, &company, nil
	}

	if err != sql.ErrNoRows {
		return nil, nil, fmt.Errorf("get company by membership: %w", err)
	}

	// Если membership нет — цепляем пользователя к первой активной компании.
	err = tx.GetContext(ctx, &company, `
		SELECT id, name, code, status, created_at, updated_at
		FROM companies
		WHERE status = 'active'
		ORDER BY created_at ASC
		LIMIT 1
	`)
	if err != nil {
		return nil, nil, fmt.Errorf("get default company: %w", err)
	}

	_, err = tx.ExecContext(ctx, `
		INSERT INTO company_users (
			id, company_id, user_id, role, status, joined_at, created_at, updated_at
		) VALUES (
			$1, $2, $3, $4, 'active', now(), now(), now()
		)
	`, uuid.New(), company.ID, user.ID, primaryRoleFromRoles(roles))
	if err != nil {
		return nil, nil, fmt.Errorf("insert company_users: %w", err)
	}

	if err := tx.Commit(); err != nil {
		return nil, nil, fmt.Errorf("commit tx: %w", err)
	}

	return &user, &company, nil
}

func (s *Store) SearchDetections(ctx context.Context, companyID string, req model.DetectionSearchRequest) ([]model.DetectionsBusiness, error) {
	fmt.Printf("DEBUG SearchDetections companyID=%q\n", companyID)
	var results []model.DetectionsBusiness
	err := s.db.SelectContext(ctx, &results, `
		SELECT det.id, det.company_id, det.flight_id, det.type, det.status, det.score, det.title, det.description,
		       det.centroid_lat, det.centroid_lon, det.area, det.last_detection_at,
		       det.created_by, det.updated_by, det.created_at, det.updated_at, det.archived_at
		FROM detections_business det
		JOIN flights f ON f.id = det.flight_id
		WHERE f.company_id = $1
		ORDER BY det.last_detection_at DESC
		LIMIT 50
	`, companyID)
	if err != nil {
		return nil, fmt.Errorf("search detections: %w", err)
	}
	return results, nil
}

var ErrNotFound = fmt.Errorf("not found")

func (s *Store) GetDetectionByID(ctx context.Context, id string, companyID string) (*model.DetectionsBusiness, error) {
	var d model.DetectionsBusiness
	err := s.db.GetContext(ctx, &d, `
		SELECT det.id, det.company_id, det.flight_id, det.type, det.status, det.score, det.title, det.description,
		       det.centroid_lat, det.centroid_lon, det.area, det.last_detection_at,
		       det.created_by, det.updated_by, det.created_at, det.updated_at, det.archived_at
		FROM detections_business det
		JOIN flights f ON f.id = det.flight_id
		WHERE det.id = $1 AND f.company_id = $2
	`, id, companyID)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, ErrNotFound
		}
		return nil, fmt.Errorf("get detection: %w", err)
	}
	return &d, nil
}

func (s *Store) GetDetectionComments(ctx context.Context, detectionID string, companyID string) ([]model.DetectionComment, error) {
	var count int
	err := s.db.QueryRowContext(ctx, `
		SELECT COUNT(*) FROM detections_business det
		JOIN flights f ON f.id = det.flight_id
		WHERE det.id = $1 AND f.company_id = $2
	`, detectionID, companyID).Scan(&count)
	if err != nil || count == 0 {
		return nil, ErrNotFound
	}

	var comments []model.DetectionComment
	comments = []model.DetectionComment{}
	err = s.db.SelectContext(ctx, &comments, `
		SELECT id, detection_id, author_user_id, body, created_at, updated_at, deleted_at
		FROM detection_comments
		WHERE detection_id = $1 AND deleted_at IS NULL
		ORDER BY created_at ASC
	`, detectionID)
	if err != nil {
		return nil, fmt.Errorf("get comments: %w", err)
	}
	return comments, nil
}

func (s *Store) CreateDetectionComment(ctx context.Context, detectionID string, companyID string, keycloakUserID string, body string) (*model.DetectionComment, error) {
	var count int
	err := s.db.QueryRowContext(ctx, `
		SELECT COUNT(*) FROM detections_business det
		JOIN flights f ON f.id = det.flight_id
		WHERE det.id = $1 AND f.company_id = $2
	`, detectionID, companyID).Scan(&count)
	if err != nil || count == 0 {
		return nil, ErrNotFound
	}

	var authorUserID string
	err = s.db.QueryRowContext(ctx, `
		SELECT id FROM users WHERE keycloak_user_id = $1
	`, keycloakUserID).Scan(&authorUserID)
	if err != nil {
		return nil, fmt.Errorf("user not found: %w", err)
	}

	var c model.DetectionComment
	err = s.db.GetContext(ctx, &c, `
		INSERT INTO detection_comments (id, detection_id, author_user_id, body, created_at, updated_at)
		VALUES (gen_random_uuid(), $1, $2, $3, now(), now())
		RETURNING id, detection_id, author_user_id, body, created_at, updated_at, deleted_at
	`, detectionID, authorUserID, body)
	if err != nil {
		fmt.Printf("ERROR CreateDetectionComment insert: %v\n", err)
		return nil, fmt.Errorf("create comment: %w", err)
	}
	return &c, nil
}

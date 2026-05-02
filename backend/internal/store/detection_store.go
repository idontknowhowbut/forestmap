package store

import (
    "context"
    "database/sql"
    "fmt"
    "forestmap/backend/internal/model"
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


func (s *Store) SearchDetections(ctx context.Context, companyID string, req model.DetectionSearchRequest) ([]model.DetectionsBusiness, error) {
    var results []model.DetectionsBusiness
    err := s.db.SelectContext(ctx, &results, `
        SELECT id, company_id, flight_id, type, status, score, title, description,
               centroid_lat, centroid_lon, area, last_detection_at,
               created_by, updated_by, created_at, updated_at, archived_at
        FROM detections_business
        WHERE company_id = $1
        ORDER BY last_detection_at DESC
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
		SELECT id, company_id, flight_id, type, status, score, title, description,
		       centroid_lat, centroid_lon, area, last_detection_at,
		       created_by, updated_by, created_at, updated_at, archived_at
		FROM detections_business
		WHERE id = $1 AND company_id = $2
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
    // проверка принадлежности
    var count int
    err := s.db.QueryRowContext(ctx, `
        SELECT COUNT(*) FROM detections_business WHERE id = $1 AND company_id = $2
    `, detectionID, companyID).Scan(&count)
    if err != nil || count == 0 {
        return nil, ErrNotFound
    }
    // получение комментариев
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
    // проверка принадлежности
    var count int
    err := s.db.QueryRowContext(ctx, `
        SELECT COUNT(*) FROM detections_business WHERE id = $1 AND company_id = $2
    `, detectionID, companyID).Scan(&count)
    if err != nil || count == 0 {
        return nil, ErrNotFound
    }

    // найти внутренний id пользователя по keycloak_user_id
    var authorUserID string
    err = s.db.QueryRowContext(ctx, `
        SELECT id FROM users WHERE keycloak_user_id = $1
    `, keycloakUserID).Scan(&authorUserID)
    if err != nil {
        return nil, fmt.Errorf("user not found: %w", err)
    }

    // INSERT
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

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

func (s *Store) EnsureUserAndCompanyByKeycloakUser(
	ctx context.Context,
	keycloakUserID string,
	email string,
	fullName string,
	roles []string,
) (*model.User, *model.Company, error) {
	keycloakUserID = strings.TrimSpace(keycloakUserID)
	email = strings.TrimSpace(email)
	fullName = strings.TrimSpace(fullName)
	if keycloakUserID == "" {
		keycloakUserID = email
	}
	if keycloakUserID == "" {
		keycloakUserID = fullName
	}
	if keycloakUserID == "" {
		return nil, nil, fmt.Errorf("empty external user id")
	}
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

	if err == sql.ErrNoRows && email != "" {
		// Dev/test seed links users to companies by stable user rows and email.
		// If Keycloak was already initialized with generated `sub` values, bind
		// the seeded user row to the current token subject instead of attaching
		// an arbitrary unknown user to the first company.
		err = tx.GetContext(ctx, &user, `
			UPDATE users
			SET keycloak_user_id = $1,
			    full_name = COALESCE(NULLIF($3, ''), full_name),
			    updated_at = now()
			WHERE lower(email) = lower($2)
			RETURNING id, keycloak_user_id, email, full_name, status, created_at, updated_at
		`, keycloakUserID, email, fullName)
	}

	if err != nil {
		if err != sql.ErrNoRows {
			return nil, nil, fmt.Errorf("get or bind user by keycloak id/email: %w", err)
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

	return nil, nil, fmt.Errorf("user %q has no active company membership", keycloakUserID)
}

package httpapi

import (
	"context"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/MicahParks/keyfunc/v3"
	"github.com/golang-jwt/jwt/v5"
)

type JWTAuth struct {
	issuer string
	jwks   keyfunc.Keyfunc
}

type KeycloakClaims struct {
	jwt.RegisteredClaims
	RealmAccess struct {
		Roles []string `json:"roles"`
	} `json:"realm_access"`
}

func NewJWTAuth(ctx context.Context, issuer, jwksURL string) (*JWTAuth, error) {
	issuer = strings.TrimSpace(strings.TrimRight(issuer, "/"))
	jwksURL = strings.TrimSpace(jwksURL)

	if issuer == "" {
		return nil, fmt.Errorf("OIDC_ISSUER is empty")
	}
	if jwksURL == "" {
		return nil, fmt.Errorf("OIDC_JWKS_URL is empty")
	}

	k, err := keyfunc.NewDefaultCtx(ctx, []string{jwksURL})
	if err != nil {
		return nil, fmt.Errorf("init jwks keyfunc: %w", err)
	}

	return &JWTAuth{
		issuer: issuer,
		jwks:   k,
	}, nil
}

func (a *JWTAuth) Require(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		_, err := a.parseBearerToken(r)
		if err != nil {
			w.Header().Set("WWW-Authenticate", `Bearer error="invalid_token"`)
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}
		next.ServeHTTP(w, r)
	}
}

func (a *JWTAuth) RequireRealmRole(role string, next http.HandlerFunc) http.HandlerFunc {
	return a.RequireAnyRealmRole([]string{role}, next)
}

func (a *JWTAuth) RequireAnyRealmRole(roles []string, next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		claims, err := a.parseBearerToken(r)
		if err != nil {
			w.Header().Set("WWW-Authenticate", `Bearer error="invalid_token"`)
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}

		if !hasAnyRealmRole(claims.RealmAccess.Roles, roles) {
			http.Error(w, "Forbidden", http.StatusForbidden)
			return
		}

		next.ServeHTTP(w, r)
	}
}

func (a *JWTAuth) parseBearerToken(r *http.Request) (*KeycloakClaims, error) {
	authz := r.Header.Get("Authorization")
	const prefix = "Bearer "

	if !strings.HasPrefix(authz, prefix) {
		return nil, fmt.Errorf("missing bearer token")
	}

	rawToken := strings.TrimSpace(strings.TrimPrefix(authz, prefix))
	if rawToken == "" {
		return nil, fmt.Errorf("empty bearer token")
	}

	claims := &KeycloakClaims{}
	parsed, err := jwt.ParseWithClaims(
		rawToken,
		claims,
		a.jwks.Keyfunc,
		jwt.WithValidMethods([]string{"RS256"}),
		jwt.WithLeeway(30*time.Second),
	)
	if err != nil || parsed == nil || !parsed.Valid {
		return nil, fmt.Errorf("invalid token: %w", err)
	}

	if strings.TrimRight(claims.Issuer, "/") != a.issuer {
		return nil, fmt.Errorf("invalid issuer")
	}

	return claims, nil
}

func hasAnyRealmRole(userRoles []string, required []string) bool {
	if len(required) == 0 {
		return true
	}

	set := make(map[string]struct{}, len(userRoles))
	for _, r := range userRoles {
		set[r] = struct{}{}
	}

	for _, need := range required {
		if _, ok := set[need]; ok {
			return true
		}
	}
	return false
}

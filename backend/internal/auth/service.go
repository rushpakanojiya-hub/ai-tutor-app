package auth

import (
	"errors"

	"ai-tutor-backend/configs"
	"ai-tutor-backend/internal/constants"
	"ai-tutor-backend/utils"
)

// ErrInvalidCredentials is returned when login email/password don't match.
var ErrInvalidCredentials = errors.New("invalid email or password")

// Service contains the business logic for authentication, independent of
// HTTP concerns (that lives in handler.go) and SQL concerns (repository.go).
type Service struct {
	repo *Repository
	cfg  *configs.Config
}

// NewService wires a Repository and Config into an auth Service.
func NewService(repo *Repository, cfg *configs.Config) *Service {
	return &Service{repo: repo, cfg: cfg}
}

// Register validates input, hashes the password, and creates the user.
// Every self-registered user starts as constants.RoleStudent — Teacher,
// Parent, and Admin accounts will be provisioned differently in a later day
// (e.g. an admin-only invite endpoint), not through this public route.
func (s *Service) Register(req RegisterRequest) error {
	if !utils.IsValidEmail(req.Email) {
		return errors.New("invalid email format")
	}
	if !utils.IsValidPassword(req.Password) {
		return errors.New("password must be at least 6 characters")
	}

	hash, err := utils.HashPassword(req.Password)
	if err != nil {
		return err
	}

	_, err = s.repo.CreateUser(req.Name, req.Email, hash, constants.RoleStudent)
	return err
}

// Login verifies credentials and, on success, returns a signed access token
// (embedding user_id, email, and role) plus the trimmed-down user object the
// Flutter app needs.
func (s *Service) Login(req LoginRequest) (*LoginResponse, error) {
	user, err := s.repo.FindByEmail(req.Email)
	if err != nil {
		if errors.Is(err, ErrUserNotFound) {
			return nil, ErrInvalidCredentials
		}
		return nil, err
	}

	if !utils.CheckPasswordHash(req.Password, user.PasswordHash) {
		return nil, ErrInvalidCredentials
	}

	token, err := utils.GenerateAccessToken(user.ID, user.Email, user.Role, s.cfg.JWTSecret, s.cfg.JWTAccessExpiryMin)
	if err != nil {
		return nil, err
	}

	return &LoginResponse{
		Token: token,
		User: AuthUserResponse{
			ID:   user.ID,
			Name: user.Name,
			Role: user.Role,
		},
	}, nil
}

// Profile returns the current user for GET /api/auth/profile.
func (s *Service) Profile(userID int) (*User, error) {
	return s.repo.FindByID(userID)
}
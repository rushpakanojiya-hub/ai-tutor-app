package auth

import (
	"errors"

	"ai-tutor-backend/configs"
	"ai-tutor-backend/internal/constants"
	"ai-tutor-backend/utils"
)

// ErrInvalidCredentials is returned when login email/password don't match.
var ErrInvalidCredentials = errors.New("invalid email or password")

// Account-status login errors - each maps to a specific user-facing message.
var (
	ErrAccountPending   = errors.New("account pending approval")
	ErrAccountRejected  = errors.New("account application rejected")
	ErrAccountSuspended = errors.New("account suspended")
	ErrAccountBlocked   = errors.New("account blocked")
)

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

// Register validates input, hashes the password, and creates a Student
// account - always active immediately. Teacher accounts go through
// RegisterTeacher instead, and start "pending" until an admin approves them.
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

	_, err = s.repo.CreateUser(req.Name, req.Email, hash, constants.RoleStudent, StatusActive)
	return err
}

// RegisterTeacher validates a teacher application, creates the user as
// "pending", and stores the extra profile details. The teacher cannot log
// in until an admin approves the account (see ApproveTeacher).
//
// QA fix ("Teacher registration transaction"): this used to call
// CreateUser then CreateTeacherProfile as two independent statements -
// if the profile insert failed, the user row was left behind with no
// profile, a broken half-registered account with no way to complete
// itself or clean up. CreateTeacherApplication now does both in a single
// transaction: either the full application is saved, or none of it is.
func (s *Service) RegisterTeacher(req TeacherApplyRequest) error {
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

	_, err = s.repo.CreateTeacherApplication(
		req.Name, req.Email, hash, constants.RoleTeacher, StatusPending,
		req.Phone, req.Qualification, req.Experience, req.Subjects, req.Bio,
	)
	return err
}

// Login verifies credentials, checks the account is active, and on success
// returns a signed access token (embedding user_id, email, and role) plus
// the trimmed-down user object the Flutter app needs.
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

	switch user.Status {
	case StatusPending:
		return nil, ErrAccountPending
	case StatusRejected:
		return nil, ErrAccountRejected
	case StatusSuspended:
		return nil, ErrAccountSuspended
	case StatusBlocked:
		return nil, ErrAccountBlocked
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

// --- Admin approval queue ---

func (s *Service) ListPendingTeachers() ([]TeacherApplication, error) {
	return s.repo.ListTeacherApplications(StatusPending)
}

// ErrNotATeacherApplication is returned by ApproveTeacher/RejectTeacher
// when the target user isn't a teacher, or isn't currently pending -
// e.g. calling approve on a student account, or on a teacher who was
// already approved/rejected.
var ErrNotATeacherApplication = errors.New("this user is not a pending teacher application")

// ApproveTeacher validates the target is an actual pending teacher
// application before approving it.
//
// QA fix ("Teacher approval validation"): previously called
// UpdateUserStatus directly with no checks at all - any user ID could
// be "approved" regardless of role or current status, including
// students, already-active teachers, or already-rejected applications.
func (s *Service) ApproveTeacher(userID int) error {
	user, err := s.repo.FindByID(userID)
	if err != nil {
		return err
	}
	if user.Role != "teacher" || user.Status != StatusPending {
		return ErrNotATeacherApplication
	}
	return s.repo.UpdateUserStatus(userID, StatusActive)
}

// RejectTeacher validates the target is an actual pending teacher
// application before rejecting it.
//
// QA fix ("Teacher rejection validation"): same gap as ApproveTeacher.
func (s *Service) RejectTeacher(userID int) error {
	user, err := s.repo.FindByID(userID)
	if err != nil {
		return err
	}
	if user.Role != "teacher" || user.Status != StatusPending {
		return ErrNotATeacherApplication
	}
	return s.repo.UpdateUserStatus(userID, StatusRejected)
}

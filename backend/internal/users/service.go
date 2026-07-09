package users

import (
	"errors"

	"ai-tutor-backend/utils"
)

var ErrIncorrectCurrentPassword = errors.New("current password is incorrect")

type Service struct {
	repo *Repository
}

func NewService(repo *Repository) *Service {
	return &Service{repo: repo}
}

func (s *Service) UpdateProfile(userID int, req UpdateProfileRequest) error {
	if !utils.IsValidEmail(req.Email) {
		return errors.New("invalid email format")
	}
	return s.repo.UpdateNameAndEmail(userID, req.Name, req.Email)
}

func (s *Service) ChangePassword(userID int, req ChangePasswordRequest) error {
	if !utils.IsValidPassword(req.NewPassword) {
		return errors.New("new password must be at least 6 characters")
	}

	currentHash, err := s.repo.GetPasswordHash(userID)
	if err != nil {
		return err
	}
	if !utils.CheckPasswordHash(req.CurrentPassword, currentHash) {
		return ErrIncorrectCurrentPassword
	}

	newHash, err := utils.HashPassword(req.NewPassword)
	if err != nil {
		return err
	}
	return s.repo.UpdatePasswordHash(userID, newHash)
}

// AssignClassSection - admin-only (enforced in the handler via role
// check), used purely for Leaderboard filtering.
func (s *Service) AssignClassSection(studentID int, req AssignClassSectionRequest) error {
	return s.repo.AssignClassSection(studentID, req.Class, req.Section)
}

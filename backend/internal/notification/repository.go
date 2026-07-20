package notification

import (
	"database/sql"
	"errors"
)

// ErrNotificationNotFound is returned when a notification id doesn't
// exist, or doesn't belong to the requesting user.
var ErrNotificationNotFound = errors.New("notification not found")

type Repository struct {
	db *sql.DB
}

func NewRepository(db *sql.DB) *Repository {
	return &Repository{db: db}
}

// Create inserts one notification for one user.
func (r *Repository) Create(userID int, notifType, title, body string, relatedID int) error {
	_, err := r.db.Exec(`
		INSERT INTO notifications (user_id, type, title, body, related_id)
		VALUES ($1, $2, $3, $4, $5)`,
		userID, notifType, title, body, relatedID,
	)
	return err
}

// CreateForUsers fans the same notification out to many users at once
// (e.g. every student, when a new live class is scheduled).
func (r *Repository) CreateForUsers(userIDs []int, notifType, title, body string, relatedID int) error {
	if len(userIDs) == 0 {
		return nil
	}
	tx, err := r.db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	for _, uid := range userIDs {
		if _, err := tx.Exec(`
			INSERT INTO notifications (user_id, type, title, body, related_id)
			VALUES ($1, $2, $3, $4, $5)`,
			uid, notifType, title, body, relatedID,
		); err != nil {
			return err
		}
	}
	return tx.Commit()
}

// AllStudentIDs is a small helper used to fan a notification out to
// every student - there's no per-class enrollment/registration in this
// app, so "every student" is the honest audience for "a new class was
// scheduled".
func (r *Repository) AllStudentIDs() ([]int, error) {
	rows, err := r.db.Query(`SELECT id FROM users WHERE role = 'student'`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var ids []int
	for rows.Next() {
		var id int
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		ids = append(ids, id)
	}
	return ids, rows.Err()
}

func (r *Repository) ListForUser(userID int) ([]Notification, error) {
	rows, err := r.db.Query(`
		SELECT id, type, title, body, related_id, is_read, created_at
		FROM notifications WHERE user_id = $1 ORDER BY created_at DESC LIMIT 50`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []Notification
	for rows.Next() {
		var n Notification
		if err := rows.Scan(&n.ID, &n.Type, &n.Title, &n.Body, &n.RelatedID, &n.IsRead, &n.CreatedAt); err != nil {
			return nil, err
		}
		result = append(result, n)
	}
	return result, rows.Err()
}

func (r *Repository) CountUnread(userID int) (int, error) {
	var count int
	err := r.db.QueryRow(`SELECT COUNT(*) FROM notifications WHERE user_id = $1 AND is_read = false`, userID).Scan(&count)
	return count, err
}

// MarkRead marks one notification as read, scoped to userID so a user
// can't mark (or even discover the existence of) someone else's
// notification by guessing an id.
//
// BUG FIX: didn't check RowsAffected - marking a nonexistent id, or one
// belonging to a different user, matched 0 rows but still reported
// success ("Marked as read") to the caller instead of surfacing that
// nothing actually happened.
func (r *Repository) MarkRead(id, userID int) error {
	res, err := r.db.Exec(`UPDATE notifications SET is_read = true WHERE id = $1 AND user_id = $2`, id, userID)
	if err != nil {
		return err
	}
	n, err := res.RowsAffected()
	if err != nil {
		return err
	}
	if n == 0 {
		return ErrNotificationNotFound
	}
	return nil
}

// MarkAllRead marks every unread notification as read. 0 rows affected
// is a legitimate outcome here (nothing was unread) rather than an
// error, unlike MarkRead above which targets one specific id.
func (r *Repository) MarkAllRead(userID int) error {
	_, err := r.db.Exec(`UPDATE notifications SET is_read = true WHERE user_id = $1 AND is_read = false`, userID)
	return err
}

package badge

import (
	"database/sql"
	"time"
)

// Passing threshold reused from quiz analytics ("weak topics"/pass-fail
// split already uses 60% elsewhere in the app).
const passingScore = 60

type Repository struct {
	db *sql.DB
}

func NewRepository(db *sql.DB) *Repository {
	return &Repository{db: db}
}

// ListAllBadges returns the 7 fixed badge definitions.
func (r *Repository) ListAllBadges() ([]Badge, error) {
	rows, err := r.db.Query(`SELECT id, key, name, description, icon_key FROM badges ORDER BY id`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []Badge
	for rows.Next() {
		var b Badge
		if err := rows.Scan(&b.ID, &b.Key, &b.Name, &b.Description, &b.IconKey); err != nil {
			return nil, err
		}
		result = append(result, b)
	}
	return result, nil
}

// EarnedByStudent returns key -> earned_at for every badge the student
// already has.
func (r *Repository) EarnedByStudent(studentID int) (map[string]time.Time, error) {
	rows, err := r.db.Query(`
		SELECT b.key, sb.earned_at
		FROM student_badges sb
		JOIN badges b ON b.id = sb.badge_id
		WHERE sb.student_id = $1`, studentID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	result := make(map[string]time.Time)
	for rows.Next() {
		var key string
		var earnedAt time.Time
		if err := rows.Scan(&key, &earnedAt); err != nil {
			return nil, err
		}
		result[key] = earnedAt
	}
	return result, nil
}

// Award inserts a new student_badges row for the given badge key - a
// no-op (via ON CONFLICT) if the student already has it.
func (r *Repository) Award(studentID int, badgeKey string) error {
	_, err := r.db.Exec(`
		INSERT INTO student_badges (student_id, badge_id, earned_at)
		SELECT $1, id, now() FROM badges WHERE key = $2
		ON CONFLICT (student_id, badge_id) DO NOTHING`, studentID, badgeKey)
	return err
}

// --- Individual achievement checks - each queries real existing data,
// no new tracking tables needed beyond student_badges/badges above. ---

func (r *Repository) PassedQuizCount(studentID int) (int, error) {
	var count int
	err := r.db.QueryRow(`SELECT COUNT(*) FROM quiz_attempts WHERE user_id = $1 AND score_percent >= $2`, studentID, passingScore).Scan(&count)
	return count, err
}

func (r *Repository) PassedMathQuizCount(studentID int) (int, error) {
	var count int
	err := r.db.QueryRow(`
		SELECT COUNT(*) FROM quiz_attempts qa
		JOIN subjects s ON s.id = qa.subject_id
		WHERE qa.user_id = $1 AND qa.score_percent >= $2 AND s.name ILIKE '%math%'`, studentID, passingScore).Scan(&count)
	return count, err
}

func (r *Repository) HasPerfectScore(studentID int) (bool, error) {
	var exists bool
	err := r.db.QueryRow(`SELECT EXISTS(SELECT 1 FROM quiz_attempts WHERE user_id = $1 AND score_percent = 100)`, studentID).Scan(&exists)
	return exists, err
}

func (r *Repository) SubmittedAssignmentCount(studentID int) (int, error) {
	var count int
	err := r.db.QueryRow(`SELECT COUNT(*) FROM assignment_submissions WHERE student_id = $1 AND status != 'draft'`, studentID).Scan(&count)
	return count, err
}

// HasFinishedAnyCourse checks if the student has completed every lesson
// in at least one subject that has at least one lesson.
func (r *Repository) HasFinishedAnyCourse(studentID int) (bool, error) {
	var exists bool
	err := r.db.QueryRow(`
		SELECT EXISTS(
			SELECT 1 FROM subjects s
			WHERE (SELECT COUNT(*) FROM lessons l WHERE l.subject_id = s.id) > 0
			AND (SELECT COUNT(*) FROM lessons l WHERE l.subject_id = s.id) = (
				SELECT COUNT(*) FROM lesson_progress lp
				JOIN lessons l2 ON l2.id = lp.lesson_id
				WHERE l2.subject_id = s.id AND lp.user_id = $1
			)
		)`, studentID).Scan(&exists)
	return exists, err
}

// HasPerfectAttendance checks if the student attended every completed
// live class in at least one subject with 3+ completed classes.
func (r *Repository) HasPerfectAttendance(studentID int) (bool, error) {
	var exists bool
	err := r.db.QueryRow(`
		SELECT EXISTS(
			SELECT 1 FROM live_classes lc
			WHERE lc.subject_id IS NOT NULL
			AND (SELECT COUNT(*) FROM live_classes lc2 WHERE lc2.subject_id = lc.subject_id AND lc2.status = 'completed') >= 3
			AND (SELECT COUNT(*) FROM live_classes lc3 WHERE lc3.subject_id = lc.subject_id AND lc3.status = 'completed') = (
				SELECT COUNT(*) FROM live_class_attendance a
				JOIN live_classes lc4 ON lc4.id = a.live_class_id
				WHERE lc4.subject_id = lc.subject_id AND lc4.status = 'completed' AND a.student_id = $1
			)
		)`, studentID).Scan(&exists)
	return exists, err
}

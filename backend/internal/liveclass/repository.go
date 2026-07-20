package liveclass

import (
	"database/sql"
	"errors"
)

var ErrNotFound = errors.New("live class not found")
var ErrForbidden = errors.New("you don't have permission to do that")

type Repository struct {
	db *sql.DB
}

func NewRepository(db *sql.DB) *Repository {
	return &Repository{db: db}
}

func (r *Repository) Create(teacherID int, req CreateRequest) (int, error) {
	var lessonID interface{}
	if req.LessonID > 0 {
		lessonID = req.LessonID
	}
	var maxStudents interface{}
	if req.MaxStudents > 0 {
		maxStudents = req.MaxStudents
	}
	var password interface{}
	if req.MeetingPassword != "" {
		password = req.MeetingPassword
	}

	var id int
	err := r.db.QueryRow(`
		INSERT INTO live_classes (teacher_id, subject_id, lesson_id, title, description, class_date, start_time, end_time, max_students, is_public, meeting_password, record_class, status)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, 'scheduled')
		RETURNING id`,
		teacherID, req.SubjectID, lessonID, req.Title, req.Description, req.ClassDate, req.StartTime, req.EndTime,
		maxStudents, req.IsPublic, password, req.RecordClass,
	).Scan(&id)
	return id, err
}

func (r *Repository) checkOwnership(classID, teacherID int) error {
	var ownerID int
	err := r.db.QueryRow(`SELECT teacher_id FROM live_classes WHERE id = $1`, classID).Scan(&ownerID)
	if err == sql.ErrNoRows {
		return ErrNotFound
	}
	if err != nil {
		return err
	}
	if ownerID != teacherID {
		return ErrForbidden
	}
	return nil
}

func (r *Repository) Update(classID, teacherID int, req UpdateRequest) error {
	if err := r.checkOwnership(classID, teacherID); err != nil {
		return err
	}
	_, err := r.db.Exec(`
		UPDATE live_classes SET
			title = COALESCE($1, title),
			description = COALESCE($2, description),
			class_date = COALESCE($3, class_date),
			start_time = COALESCE($4, start_time),
			end_time = COALESCE($5, end_time),
			max_students = COALESCE($6, max_students),
			is_public = COALESCE($7, is_public),
			meeting_password = COALESCE($8, meeting_password),
			record_class = COALESCE($9, record_class),
			updated_at = now()
		WHERE id = $10`,
		req.Title, req.Description, req.ClassDate, req.StartTime, req.EndTime,
		req.MaxStudents, req.IsPublic, req.MeetingPassword, req.RecordClass, classID,
	)
	return err
}

func (r *Repository) SetStatus(classID, teacherID int, status string) error {
	if err := r.checkOwnership(classID, teacherID); err != nil {
		return err
	}
	_, err := r.db.Exec(`UPDATE live_classes SET status = $1, updated_at = now() WHERE id = $2`, status, classID)
	return err
}

// AdminCancel bypasses the teacher-ownership check - admin can cancel
// any class platform-wide.
func (r *Repository) AdminCancel(classID int) error {
	res, err := r.db.Exec(`UPDATE live_classes SET status = $1, updated_at = now() WHERE id = $2`, StatusCancelled, classID)
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return ErrNotFound
	}
	return nil
}

// SetMeetingLive records that the teacher started the video session -
// ownership-checked.
func (r *Repository) SetMeetingLive(classID, teacherID int, roomName string) error {
	if err := r.checkOwnership(classID, teacherID); err != nil {
		return err
	}
	_, err := r.db.Exec(`
		UPDATE live_classes SET room_name = $1, meeting_status = $2, started_at = now(), updated_at = now()
		WHERE id = $3`, roomName, MeetingLive, classID)
	return err
}

// SetMeetingEnded records that the teacher ended the video session -
// ownership-checked.
func (r *Repository) SetMeetingEnded(classID, teacherID int) error {
	if err := r.checkOwnership(classID, teacherID); err != nil {
		return err
	}
	_, err := r.db.Exec(`
		UPDATE live_classes SET meeting_status = $1, ended_at = now(), updated_at = now()
		WHERE id = $2`, MeetingEnded, classID)
	return err
}

func (r *Repository) Delete(classID, teacherID int) error {
	if err := r.checkOwnership(classID, teacherID); err != nil {
		return err
	}
	_, err := r.db.Exec(`DELETE FROM live_classes WHERE id = $1`, classID)
	return err
}

// computedStatusExpr turns a stored 'scheduled' row into 'missed' once its
// end time has passed, without needing a background job.
//
// BUG FIX (timezone mismatch): class_date/start_time/end_time are plain
// DATE/TIME columns with no timezone attached (see migration 016).
// `(lc.class_date + lc.end_time)` is therefore a TIMESTAMP WITHOUT TIME
// ZONE, and comparing it directly to now() (TIMESTAMPTZ) makes Postgres
// implicitly interpret that naive timestamp using the DB SESSION's
// configured timezone - which may or may not match the timezone
// teachers actually schedule classes in. If the session defaults to UTC
// while class times are entered in India Standard Time (this app's
// target audience), "missed"/"completed" status and attendance windows
// would be off by 5.5 hours. `AT TIME ZONE 'Asia/Kolkata'` makes the
// interpretation explicit instead of relying on whatever the session
// happens to be set to. If your deployment's teachers/students are in a
// different timezone, change this literal to match.
const computedStatusExpr = `
	CASE WHEN lc.status = 'scheduled' AND lc.meeting_status != 'live'
	     AND ((lc.class_date + lc.end_time) AT TIME ZONE 'Asia/Kolkata') < now()
	THEN 'missed' ELSE lc.status END
`

const liveClassSelect = `
	SELECT lc.id, lc.teacher_id, u.name, lc.subject_id, COALESCE(s.name, ''), lc.lesson_id, COALESCE(l.title, ''),
	       lc.title, lc.description, lc.class_date::text, lc.start_time::text, lc.end_time::text,
	       lc.max_students, lc.is_public, (lc.meeting_password IS NOT NULL), lc.record_class,
	       ` + computedStatusExpr + `, COALESCE(lc.room_name, ''), lc.meeting_status, lc.locked, lc.started_at, lc.ended_at, lc.created_at
	FROM live_classes lc
	JOIN users u ON u.id = lc.teacher_id
	LEFT JOIN subjects s ON s.id = lc.subject_id
	LEFT JOIN lessons l ON l.id = lc.lesson_id
`

func scanLiveClass(row interface{ Scan(...any) error }) (LiveClass, error) {
	var c LiveClass
	var subjectID, lessonID sql.NullInt64
	var subjectName, lessonTitle sql.NullString
	var maxStudents sql.NullInt64
	err := row.Scan(
		&c.ID, &c.TeacherID, &c.TeacherName, &subjectID, &subjectName, &lessonID, &lessonTitle,
		&c.Title, &c.Description, &c.ClassDate, &c.StartTime, &c.EndTime,
		&maxStudents, &c.IsPublic, &c.HasPassword, &c.RecordClass, &c.Status,
		&c.RoomName, &c.MeetingStatus, &c.Locked, &c.StartedAt, &c.EndedAt, &c.CreatedAt,
	)
	if subjectID.Valid {
		id := int(subjectID.Int64)
		c.SubjectID = &id
	}
	c.SubjectName = subjectName.String
	if lessonID.Valid {
		id := int(lessonID.Int64)
		c.LessonID = &id
	}
	c.LessonTitle = lessonTitle.String
	if maxStudents.Valid {
		v := int(maxStudents.Int64)
		c.MaxStudents = &v
	}
	return c, err
}

func (r *Repository) GetByID(classID int) (*LiveClass, error) {
	row := r.db.QueryRow(liveClassSelect+` WHERE lc.id = $1`, classID)
	c, err := scanLiveClass(row)
	if err == sql.ErrNoRows {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	return &c, nil
}

func (r *Repository) ListForTeacher(teacherID int) ([]LiveClass, error) {
	rows, err := r.db.Query(liveClassSelect+` WHERE lc.teacher_id = $1 ORDER BY lc.class_date DESC, lc.start_time DESC`, teacherID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return scanLiveClassRows(rows)
}

// ListForStudent returns every class (open access, matching how subjects/
// lessons/assignments already work in this app - no enrollment gate).
func (r *Repository) ListForStudent() ([]LiveClass, error) {
	rows, err := r.db.Query(liveClassSelect + ` WHERE lc.is_public = true ORDER BY lc.class_date DESC, lc.start_time DESC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return scanLiveClassRows(rows)
}

func (r *Repository) ListAllForAdmin() ([]LiveClass, error) {
	rows, err := r.db.Query(liveClassSelect + ` ORDER BY lc.class_date DESC, lc.start_time DESC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return scanLiveClassRows(rows)
}

func scanLiveClassRows(rows *sql.Rows) ([]LiveClass, error) {
	var result []LiveClass
	for rows.Next() {
		c, err := scanLiveClass(rows)
		if err != nil {
			return nil, err
		}
		result = append(result, c)
	}
	return result, rows.Err()
}

func (r *Repository) GetUserName(userID int) (string, error) {
	var name string
	err := r.db.QueryRow(`SELECT name FROM users WHERE id = $1`, userID).Scan(&name)
	return name, err
}

// SetLocked toggles whether new students can join - ownership-checked.
func (r *Repository) SetLocked(classID, teacherID int, locked bool) error {
	if err := r.checkOwnership(classID, teacherID); err != nil {
		return err
	}
	_, err := r.db.Exec(`UPDATE live_classes SET locked = $1, updated_at = now() WHERE id = $2`, locked, classID)
	return err
}

// --- Attendance (self check-in) ---

// CheckIn records studentID as present/late for classID. Only allowed
// while the class's scheduled window is open (enforced in the service
// layer, which knows "now" vs the class's start/end time).
func (r *Repository) CheckIn(classID, studentID int, status string) error {
	_, err := r.db.Exec(`
		INSERT INTO live_class_attendance (live_class_id, student_id, status)
		VALUES ($1, $2, $3)
		ON CONFLICT (live_class_id, student_id) DO NOTHING`,
		classID, studentID, status,
	)
	return err
}

func (r *Repository) GetMyAttendance(classID, studentID int) (*AttendanceRecord, error) {
	var rec AttendanceRecord
	err := r.db.QueryRow(`
		SELECT student_id, checked_in_at, status FROM live_class_attendance
		WHERE live_class_id = $1 AND student_id = $2`, classID, studentID,
	).Scan(&rec.StudentID, &rec.CheckedInAt, &rec.Status)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &rec, nil
}

// ListAttendanceForClass is for the teacher - who checked in, and when.
// Ownership-checked: only the class's own teacher can see it.
func (r *Repository) ListAttendanceForClass(classID, teacherID int) ([]AttendanceRecord, error) {
	if err := r.checkOwnership(classID, teacherID); err != nil {
		return nil, err
	}
	rows, err := r.db.Query(`
		SELECT a.student_id, u.name, a.checked_in_at, a.status
		FROM live_class_attendance a
		JOIN users u ON u.id = a.student_id
		WHERE a.live_class_id = $1
		ORDER BY a.checked_in_at ASC`, classID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []AttendanceRecord
	for rows.Next() {
		var rec AttendanceRecord
		if err := rows.Scan(&rec.StudentID, &rec.StudentName, &rec.CheckedInAt, &rec.Status); err != nil {
			return nil, err
		}
		result = append(result, rec)
	}
	return result, rows.Err()
}

// GetAttendanceSummaryForStudent: attendance % across every class that
// has already ended (completed/missed) - the honest denominator, since
// there's no per-class enrollment to know who was "supposed" to attend.
//
// BUG FIX (timezone mismatch): same reasoning as computedStatusExpr above -
// `AT TIME ZONE 'Asia/Kolkata'` makes the DATE+TIME -> instant conversion
// explicit instead of depending on the DB session's timezone setting.
func (r *Repository) GetAttendanceSummaryForStudent(studentID int) (*AttendanceSummary, error) {
	summary := &AttendanceSummary{}

	err := r.db.QueryRow(`
		SELECT COUNT(*) FROM live_classes
		WHERE status = 'completed' OR (status = 'scheduled' AND ((class_date + end_time) AT TIME ZONE 'Asia/Kolkata') < now())
	`).Scan(&summary.TotalCompletedClasses)
	if err != nil {
		return nil, err
	}

	err = r.db.QueryRow(`
		SELECT COUNT(*) FROM live_class_attendance a
		JOIN live_classes lc ON lc.id = a.live_class_id
		WHERE a.student_id = $1
		AND (lc.status = 'completed' OR (lc.status = 'scheduled' AND ((lc.class_date + lc.end_time) AT TIME ZONE 'Asia/Kolkata') < now()))
	`, studentID).Scan(&summary.AttendedCount)
	if err != nil {
		return nil, err
	}

	if summary.TotalCompletedClasses > 0 {
		summary.Percentage = (float64(summary.AttendedCount) / float64(summary.TotalCompletedClasses)) * 100
	}
	return summary, nil
}

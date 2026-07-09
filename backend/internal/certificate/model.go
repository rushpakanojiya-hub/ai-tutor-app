package certificate

import "time"

// passingScore matches the threshold already used elsewhere in the app
// (quiz analytics, badge "Quiz Master" etc.) for what counts as passing.
const passingScore = 60.0

type Certificate struct {
	ID              int       `json:"id"`
	CertificateCode string    `json:"certificate_code"`
	StudentID       int       `json:"student_id"`
	StudentName     string    `json:"student_name,omitempty"`
	SubjectID       int       `json:"subject_id"`
	CourseName      string    `json:"course_name"`
	SubjectName     string    `json:"subject_name"`
	InstructorName  string    `json:"instructor_name"`
	FinalScore      float64   `json:"final_score"`
	Grade           string    `json:"grade"`
	CompletionDate  string    `json:"completion_date"` // YYYY-MM-DD
	IssueDate       time.Time `json:"issue_date"`
}

// gradeForScore mirrors typical percentage bands - certificates only
// ever get generated at passingScore (60) or above, so "F" never
// actually appears on an issued certificate.
func gradeForScore(score float64) string {
	switch {
	case score >= 90:
		return "A+"
	case score >= 80:
		return "A"
	case score >= 70:
		return "B"
	case score >= 60:
		return "C"
	default:
		return "F"
	}
}

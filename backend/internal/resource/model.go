package resource

import "time"

// ClassResource is a file a teacher uploaded for a live class - stored
// on Cloudinary, metadata kept in our own DB so students can list it
// without ever needing Cloudinary credentials.
type ClassResource struct {
	ID            int       `json:"id"`
	LiveClassID   int       `json:"live_class_id"`
	TeacherID     int       `json:"teacher_id"`
	FileName      string    `json:"file_name"`
	FileType      string    `json:"file_type"`
	FileURL       string    `json:"file_url"`
	CloudinaryID  string    `json:"-"`
	FileSizeBytes int64     `json:"file_size_bytes"`
	UploadedAt    time.Time `json:"uploaded_at"`
}

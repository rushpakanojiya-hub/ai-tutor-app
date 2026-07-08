package resource

import (
	"fmt"
	"log"
	"path/filepath"
	"strings"

	"ai-tutor-backend/internal/cloudinary"
)

var ErrNotFound = fmt.Errorf("resource not found")
var ErrForbidden = fmt.Errorf("you can only delete files you uploaded")

// Max upload size - keeps Cloudinary's free tier and mobile data usage
// reasonable. Matches the 25MB ceiling enforced in the handler.
const MaxUploadSizeBytes = 25 * 1024 * 1024

type Service struct {
	repo   *Repository
	client *cloudinary.Client
}

func NewService(repo *Repository, client *cloudinary.Client) *Service {
	return &Service{repo: repo, client: client}
}

// Upload sends the file to Cloudinary and records it against the class.
// No ownership check on the class itself here - the handler enforces
// "teacher only" at the route level via RequireTeacher middleware; a
// teacher can attach a resource to any class they're teaching, checked
// by the caller passing the already-verified teacherID.
func (s *Service) Upload(classID, teacherID int, fileBytes []byte, filename string) (*ClassResource, error) {
	fileType := detectFileType(filename)
	resourceType := cloudinaryResourceType(fileType)

	result, err := s.client.Upload(fileBytes, filename, resourceType)
	if err != nil {
		log.Printf("[resource] Cloudinary upload failed for %q: %v", filename, err)
		return nil, fmt.Errorf("upload failed: %w", err)
	}

	res := &ClassResource{
		LiveClassID:   classID,
		TeacherID:     teacherID,
		FileName:      filename,
		FileType:      fileType,
		FileURL:       result.SecureURL,
		CloudinaryID:  result.PublicID,
		FileSizeBytes: result.Bytes,
	}

	id, err := s.repo.Create(res)
	if err != nil {
		log.Printf("[resource] DB insert failed for %q: %v", filename, err)
		return nil, err
	}
	res.ID = id
	return res, nil
}

func (s *Service) ListForClass(classID int) ([]ClassResource, error) {
	return s.repo.ListForClass(classID)
}

func (s *Service) Delete(resourceID, teacherID int) error {
	res, err := s.repo.GetByID(resourceID)
	if err != nil {
		return ErrNotFound
	}
	if res.TeacherID != teacherID {
		return ErrForbidden
	}
	_ = s.client.Delete(res.CloudinaryID, cloudinaryResourceType(res.FileType)) // best-effort remote cleanup
	return s.repo.Delete(resourceID)
}

// cloudinaryResourceType maps our simple file-type label to the
// Cloudinary "resource_type" the upload/destroy endpoints need. Images
// and videos get their native type (so Cloudinary can generate
// thumbnails/transformations); everything else uses "raw", which
// Cloudinary always allows public delivery for (unlike "image", which
// blocks PDF/ZIP delivery by default on new accounts).
func cloudinaryResourceType(fileType string) string {
	switch fileType {
	case "image":
		return "image"
	case "video":
		return "video"
	default:
		return "raw"
	}
}

func detectFileType(filename string) string {
	ext := strings.ToLower(filepath.Ext(filename))
	switch ext {
	case ".pdf":
		return "pdf"
	case ".ppt", ".pptx":
		return "ppt"
	case ".doc", ".docx":
		return "doc"
	case ".xls", ".xlsx":
		return "xls"
	case ".jpg", ".jpeg", ".png", ".gif", ".webp":
		return "image"
	case ".mp4", ".mov", ".avi", ".mkv":
		return "video"
	default:
		return "file"
	}
}

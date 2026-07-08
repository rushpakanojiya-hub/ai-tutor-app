package resource

import (
	"database/sql"
)

type Repository struct {
	db *sql.DB
}

func NewRepository(db *sql.DB) *Repository {
	return &Repository{db: db}
}

func (r *Repository) Create(res *ClassResource) (int, error) {
	var id int
	err := r.db.QueryRow(`
		INSERT INTO class_resources (live_class_id, teacher_id, file_name, file_type, file_url, cloudinary_id, file_size_bytes)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
		RETURNING id`,
		res.LiveClassID, res.TeacherID, res.FileName, res.FileType, res.FileURL, res.CloudinaryID, res.FileSizeBytes,
	).Scan(&id)
	return id, err
}

func (r *Repository) ListForClass(classID int) ([]ClassResource, error) {
	rows, err := r.db.Query(`
		SELECT id, live_class_id, teacher_id, file_name, file_type, file_url, cloudinary_id, file_size_bytes, uploaded_at
		FROM class_resources WHERE live_class_id = $1 ORDER BY uploaded_at DESC`, classID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var results []ClassResource
	for rows.Next() {
		var res ClassResource
		if err := rows.Scan(&res.ID, &res.LiveClassID, &res.TeacherID, &res.FileName, &res.FileType, &res.FileURL, &res.CloudinaryID, &res.FileSizeBytes, &res.UploadedAt); err != nil {
			return nil, err
		}
		results = append(results, res)
	}
	if results == nil {
		results = []ClassResource{}
	}
	return results, nil
}

func (r *Repository) GetByID(id int) (*ClassResource, error) {
	var res ClassResource
	err := r.db.QueryRow(`
		SELECT id, live_class_id, teacher_id, file_name, file_type, file_url, cloudinary_id, file_size_bytes, uploaded_at
		FROM class_resources WHERE id = $1`, id,
	).Scan(&res.ID, &res.LiveClassID, &res.TeacherID, &res.FileName, &res.FileType, &res.FileURL, &res.CloudinaryID, &res.FileSizeBytes, &res.UploadedAt)
	if err != nil {
		return nil, err
	}
	return &res, nil
}

func (r *Repository) Delete(id int) error {
	_, err := r.db.Exec(`DELETE FROM class_resources WHERE id = $1`, id)
	return err
}

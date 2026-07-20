# apply_resource_fixes.ps1
# Run from your backend project root (e.g. C:\Users\ABC\Desktop\ai_tutor_app\backend)
# Writes: resource module fixes (rows.Err() + RowsAffected checks).
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

$root = Get-Location
Write-Host "Applying resource module fixes in $root" -ForegroundColor Cyan

# --- internal/resource/repository.go ---
New-Item -ItemType Directory -Force -Path (Join-Path $root "internal/resource") | Out-Null
$content_internal_resource_repository_go = @'
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
	// BUG FIX: was missing a rows.Err() check - a connection error mid-
	// iteration would silently return a truncated resource list instead
	// of surfacing as an error.
	if err := rows.Err(); err != nil {
		return nil, err
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
	if err == sql.ErrNoRows {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	return &res, nil
}

// BUG FIX: didn't check RowsAffected - deleting a nonexistent/already-
// deleted resource id silently "succeeded" instead of surfacing that
// nothing was actually removed.
func (r *Repository) Delete(id int) error {
	res, err := r.db.Exec(`DELETE FROM class_resources WHERE id = $1`, id)
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return ErrNotFound
	}
	return nil
}

'@
[System.IO.File]::WriteAllText((Join-Path $root "internal/resource/repository.go"), $content_internal_resource_repository_go, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  wrote internal/resource/repository.go" -ForegroundColor Green

Write-Host ""
Write-Host "Done. Next steps:" -ForegroundColor Yellow
Write-Host "  1. go build ./... to sanity check"
Write-Host "  2. cd .. ; docker compose build --no-cache backend"
Write-Host "  3. docker compose up -d --force-recreate backend"
Write-Host "  4. docker logs ai_tutor_backend --tail 15"
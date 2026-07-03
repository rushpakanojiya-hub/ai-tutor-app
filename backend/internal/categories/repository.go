package categories

import (
	"database/sql"
	"errors"
)

// ErrCategoryNotFound is returned when no category matches the given ID.
var ErrCategoryNotFound = errors.New("category not found")

// Repository handles direct SQL access for course_categories.
type Repository struct {
	db *sql.DB
}

// NewRepository builds a categories Repository around an existing *sql.DB.
func NewRepository(db *sql.DB) *Repository {
	return &Repository{db: db}
}

// FindAll returns every category, ordered by name for a stable grid layout.
func (r *Repository) FindAll() ([]Category, error) {
	rows, err := r.db.Query(`SELECT id, name, icon, created_at FROM course_categories ORDER BY name`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []Category
	for rows.Next() {
		var c Category
		var icon sql.NullString
		if err := rows.Scan(&c.ID, &c.Name, &icon, &c.CreatedAt); err != nil {
			return nil, err
		}
		c.Icon = icon.String
		result = append(result, c)
	}
	return result, nil
}

// FindByID returns a single category, or ErrCategoryNotFound.
func (r *Repository) FindByID(id int) (*Category, error) {
	query := `SELECT id, name, icon, created_at FROM course_categories WHERE id = $1`
	var c Category
	var icon sql.NullString
	err := r.db.QueryRow(query, id).Scan(&c.ID, &c.Name, &icon, &c.CreatedAt)
	if err == sql.ErrNoRows {
		return nil, ErrCategoryNotFound
	}
	if err != nil {
		return nil, err
	}
	c.Icon = icon.String
	return &c, nil
}

// Create inserts a new category and returns its generated ID.
func (r *Repository) Create(name, icon string) (int, error) {
	var id int
	query := `INSERT INTO course_categories (name, icon) VALUES ($1, $2) RETURNING id`
	err := r.db.QueryRow(query, name, icon).Scan(&id)
	return id, err
}

// SearchByName does a case-insensitive partial match, used by the global
// search endpoint (Feature 6).
func (r *Repository) SearchByName(query string) ([]Category, error) {
	rows, err := r.db.Query(
		`SELECT id, name, icon, created_at FROM course_categories WHERE name ILIKE '%' || $1 || '%' ORDER BY name`,
		query,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []Category
	for rows.Next() {
		var c Category
		var icon sql.NullString
		if err := rows.Scan(&c.ID, &c.Name, &icon, &c.CreatedAt); err != nil {
			return nil, err
		}
		c.Icon = icon.String
		result = append(result, c)
	}
	return result, nil
}
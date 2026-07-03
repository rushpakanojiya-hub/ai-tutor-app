package users

import "database/sql"

type Repository struct {
	db *sql.DB
}

func NewRepository(db *sql.DB) *Repository {
	return &Repository{db: db}
}

func (r *Repository) ListAll() ([]User, error) {
	rows, err := r.db.Query(`SELECT id, name, email, role, created_at FROM users ORDER BY id`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []User
	for rows.Next() {
		var u User
		if err := rows.Scan(&u.ID, &u.Name, &u.Email, &u.Role, &u.CreatedAt); err != nil {
			return nil, err
		}
		result = append(result, u)
	}
	return result, nil
}

func (r *Repository) UpdateName(id int, name string) error {
	_, err := r.db.Exec(`UPDATE users SET name = $1 WHERE id = $2`, name, id)
	return err
}
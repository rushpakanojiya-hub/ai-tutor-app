package constants

const (
	RoleStudent = "student"
	RoleTeacher = "teacher"
	RoleParent  = "parent"
	RoleAdmin   = "admin"
)

var AllRoles = []string{RoleStudent, RoleTeacher, RoleParent, RoleAdmin}

func IsValidRole(role string) bool {
	for _, r := range AllRoles {
		if r == role {
			return true
		}
	}
	return false
}
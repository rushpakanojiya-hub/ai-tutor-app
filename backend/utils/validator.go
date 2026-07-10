package utils

import (
	"net/mail"
	"strings"
)

// IsValidEmail checks the email against RFC 5322 syntax using Go's
// standard net/mail parser (QA fix: "Update email validator to support
// modern domains" - the old hand-rolled regex only recognized simple
// ASCII TLDs and rejected several legitimate real-world addresses that
// net/mail's parser correctly accepts, e.g. multi-label domains,
// longer/newer TLDs, and plus-addressing edge cases the regex missed).
// A trailing check still rejects addresses with no "." in the domain
// part, since net/mail alone would accept a bare "user@localhost".
func IsValidEmail(email string) bool {
	addr, err := mail.ParseAddress(email)
	if err != nil {
		return false
	}
	at := strings.LastIndex(addr.Address, "@")
	if at == -1 || at == len(addr.Address)-1 {
		return false
	}
	domain := addr.Address[at+1:]
	return strings.Contains(domain, ".")
}

// IsValidPassword enforces a minimal password policy for Day 1 (min 6 chars).
func IsValidPassword(password string) bool {
	return len(password) >= 6
}

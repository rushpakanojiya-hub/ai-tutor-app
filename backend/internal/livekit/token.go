// Package livekit wraps the LiveKit server SDK: generating join tokens
// and creating/ending rooms. This is the only place that talks to
// LiveKit directly - the rest of the backend (internal/liveclass) calls
// this package's small interface, so swapping to Agora/100ms/Twilio/Daily
// later only means rewriting this package, not liveclass.
//
// Requires (run in backend/):
//   go get github.com/livekit/protocol
//   go get github.com/livekit/server-sdk-go/v2
package livekit

import (
	"time"

	"github.com/livekit/protocol/auth"
)

// TokenService generates signed JWTs that the Flutter app hands to the
// LiveKit client SDK to join a room.
type TokenService struct {
	apiKey    string
	apiSecret string
}

func NewTokenService(apiKey, apiSecret string) *TokenService {
	return &TokenService{apiKey: apiKey, apiSecret: apiSecret}
}

// GenerateToken builds a join token for one participant. isModerator
// grants RoomAdmin (used for teachers - lets them mute/remove others via
// the LiveKit SDK); students get publish/subscribe only.
func (s *TokenService) GenerateToken(roomName, identity, displayName string, isModerator bool) (string, error) {
	canPublish := true
	canSubscribe := true

	grant := &auth.VideoGrant{
		RoomJoin:     true,
		Room:         roomName,
		CanPublish:   &canPublish,
		CanSubscribe: &canSubscribe,
		RoomAdmin:    isModerator,
	}

	token := auth.NewAccessToken(s.apiKey, s.apiSecret).
		AddGrant(grant).
		SetIdentity(identity).
		SetName(displayName).
		SetValidFor(4 * time.Hour)

	return token.ToJWT()
}

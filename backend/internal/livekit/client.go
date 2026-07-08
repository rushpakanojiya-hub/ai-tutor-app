package livekit

import (
	"context"
	"fmt"

	"github.com/livekit/protocol/livekit"
	lksdk "github.com/livekit/server-sdk-go/v2"
)

// RoomClient manages LiveKit rooms and participants server-side (create
// on class start, delete on class end, mute/remove a disruptive
// participant, mute everyone) via LiveKit's admin API. This is the only
// place that talks to LiveKit's server SDK directly - swapping providers
// later means rewriting this file, not the callers.
type RoomClient struct {
	client *lksdk.RoomServiceClient
}

func NewRoomClient(url, apiKey, apiSecret string) *RoomClient {
	return &RoomClient{client: lksdk.NewRoomServiceClient(url, apiKey, apiSecret)}
}

// EnsureRoom creates the room if it doesn't already exist. LiveKit rooms
// are otherwise created lazily on first join, but creating explicitly
// lets us fail fast on Start if LiveKit is unreachable/misconfigured.
func (r *RoomClient) EnsureRoom(ctx context.Context, roomName string) error {
	_, err := r.client.CreateRoom(ctx, &livekit.CreateRoomRequest{Name: roomName})
	return err
}

// EndRoom forcibly disconnects everyone and removes the room.
func (r *RoomClient) EndRoom(ctx context.Context, roomName string) error {
	_, err := r.client.DeleteRoom(ctx, &livekit.DeleteRoomRequest{Room: roomName})
	return err
}

// ListParticipants returns everyone currently in the room, with their
// published track SIDs (needed to target a specific track for muting).
func (r *RoomClient) ListParticipants(ctx context.Context, roomName string) ([]*livekit.ParticipantInfo, error) {
	res, err := r.client.ListParticipants(ctx, &livekit.ListParticipantsRequest{Room: roomName})
	if err != nil {
		return nil, err
	}
	return res.Participants, nil
}

// MuteParticipant finds the given participant's audio track(s) in the
// room and mutes them server-side - the participant's mic goes silent
// immediately regardless of their own mute button. One-directional by
// design: the student can re-enable their own mic afterwards if the
// teacher allows it - there's no separate "unmute" admin action.
func (r *RoomClient) MuteParticipant(ctx context.Context, roomName, identity string) error {
	participants, err := r.ListParticipants(ctx, roomName)
	if err != nil {
		return err
	}

	var target *livekit.ParticipantInfo
	for _, p := range participants {
		if p.Identity == identity {
			target = p
			break
		}
	}
	if target == nil {
		return fmt.Errorf("participant %q not found in room %q", identity, roomName)
	}

	mutedAny := false
	for _, track := range target.Tracks {
		if track.Type == livekit.TrackType_AUDIO {
			_, err := r.client.MutePublishedTrack(ctx, &livekit.MuteRoomTrackRequest{
				Room:     roomName,
				Identity: identity,
				TrackSid: track.Sid,
				Muted:    true,
			})
			if err != nil {
				return err
			}
			mutedAny = true
		}
	}
	if !mutedAny {
		return fmt.Errorf("participant %q has no audio track to mute", identity)
	}
	return nil
}

// MuteAllExcept mutes every participant's audio in the room except the
// given identity (the teacher calling this).
func (r *RoomClient) MuteAllExcept(ctx context.Context, roomName, exceptIdentity string) error {
	participants, err := r.ListParticipants(ctx, roomName)
	if err != nil {
		return err
	}
	for _, p := range participants {
		if p.Identity == exceptIdentity {
			continue
		}
		for _, track := range p.Tracks {
			if track.Type == livekit.TrackType_AUDIO {
				_, _ = r.client.MutePublishedTrack(ctx, &livekit.MuteRoomTrackRequest{
					Room:     roomName,
					Identity: p.Identity,
					TrackSid: track.Sid,
					Muted:    true,
				}) // best-effort per participant - one failure shouldn't stop the rest
			}
		}
	}
	return nil
}

// RemoveParticipant forcibly disconnects one participant from the room.
func (r *RoomClient) RemoveParticipant(ctx context.Context, roomName, identity string) error {
	_, err := r.client.RemoveParticipant(ctx, &livekit.RoomParticipantIdentity{Room: roomName, Identity: identity})
	return err
}

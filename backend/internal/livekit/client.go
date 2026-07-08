package livekit

import (
	"context"

	"github.com/livekit/protocol/livekit"
	lksdk "github.com/livekit/server-sdk-go/v2"
)

// RoomClient manages LiveKit rooms server-side (create on class start,
// delete on class end) via LiveKit's admin API.
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

package ws

import (
	"encoding/json"
	"megaserver/internal/rooms"
	"net/http"
	"sync"

	"github.com/gorilla/websocket"
)

var AllRooms rooms.RoomMap

func (app *application) createRoomRequestHandler(w http.ResponseWriter, r *http.Request) {
	// TODO move this into middleware
	w.Header().Set("Access-Control-Allow-Origin", "*")

	roomID := AllRooms.CreateRoom()

	type resp struct {
		RoomID string `json:"room_id"`
	}

	app.logger.Info("room created", "roomID", roomID)
	json.NewEncoder(w).Encode(resp{RoomID: roomID})
}

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool {
		return true
	},
}

type broadcastMsg struct {
	Message map[string]any
	RoomID  string
	Client  *websocket.Conn
}

var broadcast = make(chan broadcastMsg)
var done = make(chan struct{})

func shutdown() {
	close(done)
}

// connMu holds a per-connection write mutex to prevent concurrent writes.
var (
	connMu   = make(map[*websocket.Conn]*sync.Mutex)
	connMuMu sync.Mutex
)

func getConnMu(conn *websocket.Conn) *sync.Mutex {
	connMuMu.Lock()
	defer connMuMu.Unlock()
	if _, ok := connMu[conn]; !ok {
		connMu[conn] = &sync.Mutex{}
	}
	return connMu[conn]
}

func removeConnMu(conn *websocket.Conn) {
	connMuMu.Lock()
	defer connMuMu.Unlock()
	delete(connMu, conn)
}

// sendJSON safely writes a JSON message to a connection with mutex protection.
func sendJSON(conn *websocket.Conn, msg any) error {
	mu := getConnMu(conn)
	mu.Lock()
	defer mu.Unlock()
	return conn.WriteJSON(msg)
}

// signalingMessage represents an incoming message from a client.
type signalingMessage struct {
	Type         string           `json:"type"`
	PeerID       string           `json:"peerId,omitempty"`
	Offer        *json.RawMessage `json:"offer,omitempty"`
	Answer       *json.RawMessage `json:"answer,omitempty"`
	ICECandidate *json.RawMessage `json:"iceCandidate,omitempty"`
}

func (app *application) joinRoomRequestHandler(w http.ResponseWriter, r *http.Request) {
	// TODO break this out into a util or middleware
	roomID, ok := r.URL.Query()["roomID"]
	if !ok {
		// TODO make this a structured error
		app.logger.Error("RoomID missing in URL Parameters")
		return
	}

	ws, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		// TODO make this a structured error
		app.logger.Error("Web Socket Upgrade Error", "error", err)
		return
	}

	peerID := rooms.GeneratePeerID()

	AllRooms.InsertIntoRoom(roomID[0], peerID, false, ws)

	app.logger.Info("peer joined", "roomID", roomID[0], "peerID", peerID)

	// send the peer their own ID immediately after connection
	sendJSON(ws, map[string]any{
		"type":     "client-id",
		"clientId": peerID,
	})

	defer app.leave(roomID[0], peerID, ws)

	shutdownDone := make(chan struct{})
	defer close(shutdownDone)

	app.background(func() {
		select {
		case <-done:
			ws.Close()
		case <-shutdownDone:
			return
		}
	})

	for {
		var msg signalingMessage

		err := ws.ReadJSON(&msg)

		if err != nil {
			select {
			case <-done:
				app.logger.Info("shutdown signal received, closing connection", "peerID", peerID)
			default:
				if websocket.IsCloseError(err, websocket.CloseNormalClosure, websocket.CloseGoingAway, websocket.CloseNoStatusReceived) {
					app.logger.Info("client disconnected", "roomID", roomID[0], "peerID", peerID)
				} else {
					app.logger.Error("Read Error", "error", err, "peerID", peerID)
				}
			}
			return
		}

		switch msg.Type {
		case "join":
			// Send the joining peer the list of existing peers
			existingPeers := AllRooms.GetPeerIDs(roomID[0], peerID)
			sendJSON(ws, map[string]any{
				"type":  "peers-list",
				"peers": existingPeers,
			})

			// Notify all existing peers that a new peer joined
			for _, existingPeerID := range existingPeers {
				if conn := AllRooms.GetConnByPeerID(roomID[0], existingPeerID); conn != nil {
					sendJSON(conn, map[string]any{
						"type":   "peer-joined",
						"peerId": peerID,
					})
				}
			}

		case "leave":
			return // triggers deferred app.leave()

		case "offer":
			if msg.Offer != nil && msg.PeerID != "" {
				if conn := AllRooms.GetConnByPeerID(roomID[0], msg.PeerID); conn != nil {
					sendJSON(conn, map[string]any{
						"type":   "offer",
						"peerId": peerID, // tell the recipient WHO sent the offer
						"offer":  msg.Offer,
					})
				}
			}

		case "answer":
			if msg.Answer != nil && msg.PeerID != "" {
				if conn := AllRooms.GetConnByPeerID(roomID[0], msg.PeerID); conn != nil {
					sendJSON(conn, map[string]any{
						"type":   "answer",
						"peerId": peerID,
						"answer": msg.Answer,
					})
				}
			}

		case "ice-candidate":
			if msg.ICECandidate != nil && msg.PeerID != "" {
				if conn := AllRooms.GetConnByPeerID(roomID[0], msg.PeerID); conn != nil {
					sendJSON(conn, map[string]any{
						"type":         "ice-candidate",
						"peerId":       peerID,
						"iceCandidate": msg.ICECandidate,
					})
				}
			}

		default:
			app.logger.Warn("unhandled message type", "type", msg.Type)
		}
	}
}

func (app *application) leave(roomID, peerID string, ws *websocket.Conn) {
	removedPeerID := AllRooms.RemoveFromRoom(roomID, ws)
	removeConnMu(ws)
	ws.Close()

	if removedPeerID == "" {
		removedPeerID = peerID
	}

	// Notify remaining peers that this peer left
	participants := AllRooms.Get(roomID)
	for _, p := range participants {
		sendJSON(p.Conn, map[string]any{
			"type":   "peer-left",
			"peerId": removedPeerID,
		})
	}

	app.logger.Info("peer left", "roomID", roomID, "peerID", removedPeerID)
}

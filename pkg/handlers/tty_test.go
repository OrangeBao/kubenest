package handlers

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gorilla/websocket"
	"github.com/stretchr/testify/assert"
)

func startTestTTYServer() *httptest.Server {
	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		NewTTYHandler().ServeHTTP(w, r)
	}))
}

func TestTTYHandler(t *testing.T) {
	t.Run("TestTTY", func(t *testing.T) {
		server := startTestTTYServer()
		defer server.Close()

		u := "ws" + strings.TrimPrefix(server.URL, "http") + "?command=echo"

		ws, res, err := websocket.DefaultDialer.Dial(u, nil)
		assert.NoError(t, err)
		if res != nil {
			defer res.Body.Close()
		}
		defer ws.Close()

		// Simulating the PTY interaction by writing a message into the TTY pseudo-terminal
		echoMessage := "Hello"
		go func() {
			err := ws.WriteMessage(websocket.TextMessage, []byte(echoMessage))
			assert.NoError(t, err)
		}()

		var output strings.Builder
		for {
			messageType, message, err := ws.ReadMessage()
			if err != nil {
				break
			}
			if messageType == websocket.CloseMessage {
				break
			}
			output.Write(message)
		}

		assert.Equal(t, "Hello\r\n", output.String())
	})
}

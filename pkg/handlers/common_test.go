/*
Copyright 2024 The KubeNest Authors.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package handlers

import (
	"net/http"
	"net/http/httptest"
	"net/url"
	"os/exec"
	"strings"
	"testing"

	"github.com/gorilla/websocket"
	"github.com/stretchr/testify/assert"
)

func TestHandleWebSocketUpgrade(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		HandleWebSocketUpgrade(w, r, func(conn *websocket.Conn, _ url.Values) {
			messageType, message, err := conn.ReadMessage()
			assert.NoError(t, err)
			assert.Equal(t, websocket.TextMessage, messageType)
			err = conn.WriteMessage(websocket.TextMessage, message)
			assert.NoError(t, err)
		})
	}))
	defer server.Close()

	u := "ws" + strings.TrimPrefix(server.URL, "http")

	ws, res, err := websocket.DefaultDialer.Dial(u, nil)
	assert.NoError(t, err)
	if res != nil {
		defer res.Body.Close()
	}
	defer ws.Close()

	testMessage := "测试消息"
	err = ws.WriteMessage(websocket.TextMessage, []byte(testMessage))
	assert.NoError(t, err)

	messageType, message, err := ws.ReadMessage()
	assert.NoError(t, err)
	assert.Equal(t, websocket.TextMessage, messageType)
	assert.Equal(t, testMessage, string(message))
}

func TestCmd(t *testing.T) {
	execCommand = func(name string, args ...string) *exec.Cmd {
		if name == "echo" {
			return exec.Command("echo", args...)
		}
		return exec.Command("nonexistentcommand")
	}

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		HandleWebSocketUpgrade(w, r, func(conn *websocket.Conn, params url.Values) {
			command := params.Get("command")
			args := params["args"]
			Cmd(conn, command, args)
		})
	}))
	defer server.Close()

	u := "ws" + strings.TrimPrefix(server.URL, "http") + "?command=echo&args=hello&args=world"

	ws, res, err := websocket.DefaultDialer.Dial(u, nil)
	assert.NoError(t, err)
	if res != nil {
		defer res.Body.Close()
	}
	defer ws.Close()

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

	assert.Equal(t, "hello world", output.String())
}

func TestCmd_InvalidCommand(t *testing.T) {
	execCommand = exec.Command

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		HandleWebSocketUpgrade(w, r, func(conn *websocket.Conn, params url.Values) {
			command := params.Get("command")
			args := params["args"]
			Cmd(conn, command, args)
		})
	}))
	defer server.Close()

	u := "ws" + strings.TrimPrefix(server.URL, "http") + "?command=invalidcommand"

	ws, res, err := websocket.DefaultDialer.Dial(u, nil)
	assert.NoError(t, err)
	if res != nil {
		defer res.Body.Close()
	}
	defer ws.Close()

	messageType, message, err := ws.ReadMessage()
	assert.NoError(t, err)
	assert.Equal(t, websocket.TextMessage, messageType)
	assert.Contains(t, strings.ToLower(string(message)), "executable file not found")
}

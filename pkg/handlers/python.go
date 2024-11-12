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
	"net/url"
	"os"

	"github.com/gorilla/websocket"
)

func NewPythonHandler() http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		HandleWebSocketUpgrade(w, r, func(conn *websocket.Conn, values url.Values) {
			handleScript(conn, values, []string{"python3", "-u"})
		})
	})
}

func handleScript(conn *websocket.Conn, params url.Values, command []string) {
	args := params["args"]
	if len(args) == 0 {
		_ = conn.WriteMessage(websocket.TextMessage, []byte("No command specified"))
	}
	// Write data to a temporary file
	tempFile, err := os.CreateTemp("", "script_*")
	if err != nil {
		LOG.Errorf("Error creating temporary file: %v", err)
		return
	}
	defer os.Remove(tempFile.Name()) // Clean up temporary file
	defer tempFile.Close()
	tempFilefp, err := os.OpenFile(tempFile.Name(), os.O_APPEND|os.O_WRONLY, 0644)
	if err != nil {
		LOG.Errorf("Error opening temporary file: %v", err)
	}
	for {
		// Read message from WebSocket client
		_, data, err := conn.ReadMessage()
		if err != nil {
			LOG.Errorf("failed to read message : %s", err)
			break
		}
		if string(data) == "EOF" {
			LOG.Infof("finish file data transfer %s", tempFile.Name())
			break
		}

		// Write received data to the temporary file
		if _, err := tempFilefp.Write(data); err != nil {
			LOG.Errorf("Error writing data to temporary file: %v", err)
			continue
		}
	}
	executeCmd := append(command, tempFile.Name())
	executeCmd = append(executeCmd, args...)
	// Execute the Python script
	Cmd(conn, executeCmd[0], executeCmd[1:])
}

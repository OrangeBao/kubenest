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
	"strings"
	"testing"

	"github.com/gorilla/websocket"
	"github.com/stretchr/testify/assert"
)

func startTestCmdServer() *httptest.Server {
	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		NewCmdHandler().ServeHTTP(w, r)
	}))
}

func TestTestCmdServer(t *testing.T) {
	t.Run("TestCmdServer", func(t *testing.T) {
		server := startTestCmdServer()
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
	})
}

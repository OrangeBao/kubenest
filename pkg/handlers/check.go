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
	"fmt"
	"net"
	"net/http"
	"net/url"

	"github.com/gorilla/websocket"

	"github.com/kosmos.io/kubenest/pkg/handlers/common"
)

func NewCheckHandler() http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		common.HandleWebSocketUpgrade(w, r, handleCheck)
	})
}

func handleCheck(conn *websocket.Conn, params url.Values) {
	port := params.Get("port")
	if len(port) == 0 {
		common.LOG.Errorf("port is required")
		return
	}
	common.LOG.Infof("Check port %s", port)
	address := fmt.Sprintf(":%s", port)
	listener, err := net.Listen("tcp", address)
	if err != nil {
		common.LOG.Infof("port not avalible %s %v", address, err)
		_ = conn.WriteMessage(websocket.CloseMessage, websocket.FormatCloseMessage(websocket.CloseNormalClosure, fmt.Sprintf("%d", 1)))
		return
	}
	defer listener.Close()
	common.LOG.Infof("port avalible %s", address)
	// _ = conn.WriteMessage(websocket.BinaryMessage, []byte("0"))
	_ = conn.WriteMessage(websocket.CloseMessage, websocket.FormatCloseMessage(websocket.CloseNormalClosure, fmt.Sprintf("%d", 0)))
}

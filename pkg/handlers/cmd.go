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

	"github.com/gorilla/websocket"
)

func NewCmdHandler() http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		HandleWebSocketUpgrade(w, r, handleCmd)
	})
}

/*
0 → success
non-zero → failure
Exit code 1 indicates a general failure
Exit code 2 indicates incorrect use of shell builtins
Exit codes 3-124 indicate some error in job (check software exit codes)
Exit code 125 indicates out of memory
Exit code 126 indicates command cannot execute
Exit code 127 indicates command not found
Exit code 128 indicates invalid argument to exit
Exit codes 129-192 indicate jobs terminated by Linux signals
For these, subtract 128 from the number and match to signal code
Enter kill -l to list signal codes
Enter man signal for more information
*/
func handleCmd(conn *websocket.Conn, params url.Values) {
	command := params.Get("command")
	args := params["args"]
	// if the command is file, the file should have execute permission
	if command == "" {
		LOG.Warnf("No command specified %v", params)
		_ = conn.WriteMessage(websocket.TextMessage, []byte("No command specified"))
		return
	}
	Cmd(conn, command, args)
}

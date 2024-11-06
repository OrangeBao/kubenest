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

package common

import (
	"bufio"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"os/exec"
	"strings"

	"github.com/gorilla/websocket"

	"github.com/kosmos.io/kubenest/pkg/logger"
)

var (
	LOG      = logger.GetLogger()
	upgrader = websocket.Upgrader{
		ReadBufferSize:  1024,
		WriteBufferSize: 1024,
		CheckOrigin: func(_ *http.Request) bool {
			return true
		},
	}

	execCommand = exec.Command
)

func HandleWebSocketUpgrade(w http.ResponseWriter, r *http.Request, handler func(*websocket.Conn, url.Values)) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		LOG.Errorf("WebSocket upgrade failed: %v", err)
		return
	}
	defer conn.Close()

	queryParams := r.URL.Query()
	handler(conn, queryParams)
}

func Cmd(conn *websocket.Conn, command string, args []string) {
	// #nosec G204
	cmd := execCommand(command, args...)
	LOG.Infof("Executing command: %s, %v", command, args)
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		LOG.Warnf("Error obtaining command output pipe: %v", err)
	}
	defer stdout.Close()

	stderr, err := cmd.StderrPipe()
	if err != nil {
		LOG.Warnf("Error obtaining command error pipe: %v", err)
	}
	defer stderr.Close()

	// Channel for signaling command completion
	doneCh := make(chan struct{})
	defer close(doneCh)
	// processOutput
	go func() {
		scanner := bufio.NewScanner(stdout)
		for scanner.Scan() {
			data := scanner.Bytes()
			LOG.Warnf("%s", data)
			_ = conn.WriteMessage(websocket.TextMessage, data)
		}
		scanner = bufio.NewScanner(stderr)
		for scanner.Scan() {
			data := scanner.Bytes()
			LOG.Warnf("%s", data)
			_ = conn.WriteMessage(websocket.TextMessage, data)
		}
		doneCh <- struct{}{}
	}()
	if err := cmd.Start(); err != nil {
		errStr := strings.ToLower(err.Error())
		LOG.Warnf("Error starting command: %v, %s", err, errStr)
		_ = conn.WriteMessage(websocket.TextMessage, []byte(errStr))
		if strings.Contains(errStr, "no such file") {
			exitCode := 127
			_ = conn.WriteMessage(websocket.CloseMessage, websocket.FormatCloseMessage(websocket.CloseNormalClosure, fmt.Sprintf("%d", exitCode)))
		}
	}

	// Wait for the command to finish
	if err := cmd.Wait(); err != nil {
		var exitError *exec.ExitError
		if errors.As(err, &exitError) {
			LOG.Warnf("Command : %s exited with non-zero status: %v", command, exitError)
		}
	}
	<-doneCh
	exitCode := cmd.ProcessState.ExitCode()
	LOG.Infof("Command : %s finished with exit code %d", command, exitCode)
	_ = conn.WriteMessage(websocket.CloseMessage, websocket.FormatCloseMessage(websocket.CloseNormalClosure, fmt.Sprintf("%d", exitCode)))
}

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
	"os/exec"
	"os/signal"
	"syscall"

	"github.com/creack/pty"
	"github.com/gorilla/websocket"

	"github.com/kosmos.io/kubenest/pkg/handlers/common"
)

func NewTTYHandler() http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		common.HandleWebSocketUpgrade(w, r, handleTty)
	})
}

func handleTty(conn *websocket.Conn, queryParams url.Values) {
	entrypoint := queryParams.Get("command")
	if len(entrypoint) == 0 {
		common.LOG.Errorf("command is required")
		return
	}
	common.LOG.Infof("Executing command %s", entrypoint)
	cmd := exec.Command(entrypoint)
	ptmx, err := pty.Start(cmd)
	if err != nil {
		common.LOG.Errorf("failed to start command %v", err)
		return
	}
	defer func() {
		_ = ptmx.Close()
	}()
	ch := make(chan os.Signal, 1)
	signal.Notify(ch, syscall.SIGWINCH)
	go func() {
		for range ch {
			if err := pty.InheritSize(os.Stdin, ptmx); err != nil {
				common.LOG.Errorf("error resizing pty: %s", err)
			}
		}
	}()
	ch <- syscall.SIGWINCH                        // Initial resize.
	defer func() { signal.Stop(ch); close(ch) }() // Cleanup signals when done.
	done := make(chan struct{})
	// Use a goroutine to copy PTY output to WebSocket
	go func() {
		buf := make([]byte, 1024)
		for {
			n, err := ptmx.Read(buf)
			if err != nil {
				common.LOG.Errorf("PTY read error: %v", err)
				break
			}
			common.LOG.Printf("Received message: %s", buf[:n])
			if err := conn.WriteMessage(websocket.BinaryMessage, buf[:n]); err != nil {
				common.LOG.Errorf("WebSocket write error: %v", err)
				break
			}
		}
		done <- struct{}{}
	}()
	// echo off
	//ptmx.Write([]byte("stty -echo\n"))
	// Set stdin in raw mode.
	//oldState, err := term.MakeRaw(int(ptmx.Fd()))
	//if err != nil {
	//	panic(err)
	//}
	//defer func() { _ = term.Restore(int(ptmx.Fd()), oldState) }() // Best effort.

	// Disable Bracketed Paste Mode in bash shell
	//	_, err = ptmx.Write([]byte("printf '\\e[?2004l'\n"))
	//	if err != nil {
	//		log.Fatal(err)
	//	}

	// Use a goroutine to copy WebSocket input to PTY
	go func() {
		for {
			_, message, err := conn.ReadMessage()
			if err != nil {
				common.LOG.Printf("read from websocket failed: %v, %s", err, string(message))
				break
			}
			common.LOG.Printf("Received message: %s", message) // Debugging line
			if _, err := ptmx.Write(message); err != nil {     // Ensure newline character for commands
				common.LOG.Printf("PTY write error: %v", err)
				break
			}
		}
		// Signal the done channel when this goroutine finishes
		done <- struct{}{}
	}()

	// Wait for the done channel to be closed
	<-done
}

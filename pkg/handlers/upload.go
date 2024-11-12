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
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"time"

	"github.com/gorilla/websocket"
)

func NewUploadHandler() http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		HandleWebSocketUpgrade(w, r, handleUpload)
	})
}

// todo file lock
func handleUpload(conn *websocket.Conn, params url.Values) {
	fileName := params.Get("file_name")
	filePath := params.Get("file_path")
	LOG.Infof("Uploading file name %s, file path %s", fileName, filePath)
	if len(fileName) != 0 && len(filePath) != 0 {
		// mkdir
		err := os.MkdirAll(filePath, 0775)
		if err != nil {
			LOG.Errorf("mkdir: %s %v", filePath, err)
			_ = conn.WriteMessage(websocket.CloseMessage, websocket.FormatCloseMessage(websocket.CloseInternalServerErr, fmt.Sprintf("failed to make directory: %v", err)))
			return
		}
		file := filepath.Join(filePath, fileName)
		// check if the file already exists
		if _, err := os.Stat(file); err == nil {
			LOG.Infof("File %s already exists", file)
			timestamp := time.Now().Format("2006-01-02-150405000")
			bakFilePath := fmt.Sprintf("%s_%s_bak", file, timestamp)
			err = os.Rename(file, bakFilePath)
			if err != nil {
				LOG.Errorf("failed to rename file: %v", err)
				_ = conn.WriteMessage(websocket.CloseMessage, websocket.FormatCloseMessage(websocket.CloseInternalServerErr, fmt.Sprintf("failed to rename file: %v", err)))
				return
			}
		}
		// create file with append
		fp, err := os.OpenFile(file, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
		if err != nil {
			LOG.Errorf("failed to open file: %v", err)
			_ = conn.WriteMessage(websocket.CloseMessage, websocket.FormatCloseMessage(websocket.CloseInternalServerErr, fmt.Sprintf("failed to open file: %v", err)))
			return
		}
		defer fp.Close()
		// receive data from websocket
		for {
			_, data, err := conn.ReadMessage()
			if err != nil {
				LOG.Errorf("failed to read message : %s", err)
				_ = conn.WriteMessage(websocket.CloseMessage, websocket.FormatCloseMessage(websocket.CloseInternalServerErr, fmt.Sprintf("failed to read message: %v", err)))
				return
			}
			// check if the file end
			if string(data) == "EOF" {
				LOG.Infof("finish file data transfer %s", file)
				_ = conn.WriteMessage(websocket.CloseMessage, websocket.FormatCloseMessage(websocket.CloseNormalClosure, fmt.Sprintf("%d", 0)))
				return
			}
			// data to file
			_, err = fp.Write(data)
			if err != nil {
				LOG.Errorf("failed to write data to file : %s", err)
				_ = conn.WriteMessage(websocket.CloseMessage, websocket.FormatCloseMessage(websocket.CloseInternalServerErr, fmt.Sprintf("failed write data to file: %v", err)))
				return
			}
		}
	}
	_ = conn.WriteMessage(websocket.CloseMessage, websocket.FormatCloseMessage(websocket.CloseInvalidFramePayloadData, "Invalid file_name or file_path"))
}

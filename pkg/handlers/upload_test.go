package handlers

import (
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/gorilla/websocket"
	"github.com/stretchr/testify/assert"
)

func startTestUploadServer() *httptest.Server {
	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		NewUploadHandler().ServeHTTP(w, r)
	}))
}

func TestUploadHandler(t *testing.T) {
	t.Run("TestUpload", func(t *testing.T) {
		server := startTestUploadServer()
		defer server.Close()

		fileName := "test.txt"
		filePath := "./test_data"

		// Ensure clean state
		os.RemoveAll(filePath)
		defer os.RemoveAll(filePath)

		u := "ws" + server.URL[4:] + "?" + url.Values{
			"file_name": {fileName},
			"file_path": {filePath},
		}.Encode()

		ws, res, err := websocket.DefaultDialer.Dial(u, nil)
		assert.NoError(t, err)
		if res != nil {
			defer res.Body.Close()
		}
		defer ws.Close()

		// Test uploading data
		testData := []byte("Hello, World!")
		err = ws.WriteMessage(websocket.TextMessage, testData)
		assert.NoError(t, err)

		// Send EOF to indicate upload end
		err = ws.WriteMessage(websocket.TextMessage, []byte("EOF"))
		assert.NoError(t, err)

		// Wait for file exists
		time.Sleep(100 * time.Millisecond)
		expectedFilePath := filepath.Join(filePath, fileName)
		// Check if file exists
		_, err = os.Stat(expectedFilePath)
		assert.NoError(t, err)

		// Check file content
		content, err := os.ReadFile(expectedFilePath)
		assert.NoError(t, err)
		assert.Equal(t, testData, content)
	})
}

package handlers

import (
	"log"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"testing"

	"github.com/gorilla/websocket"
	"github.com/stretchr/testify/assert"
)

func startTestCheckPortServer() *httptest.Server {
	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		NewCheckPortHandler().ServeHTTP(w, r)
	}))
}

func TestPortCheckHandler(t *testing.T) {
	t.Run("TestPortAvailable", func(t *testing.T) {
		server := startTestCheckPortServer()
		defer server.Close()
		// 将服务器的URL更换为ws协议，构建WebSocket连接URL
		wsURL := "ws" + server.URL[len("http"):]

		u, err := url.Parse(wsURL)
		assert.NoError(t, err)
		u.RawQuery = "port=9999"
		// 创建连接WebSocket的客户端
		header := http.Header{}
		conn, resp, _ := websocket.DefaultDialer.Dial(u.String(), header)
		defer resp.Body.Close()
		defer conn.Close()

		messageType, _, err := conn.ReadMessage()
		if err != nil {
			return
		}
		if messageType == websocket.CloseMessage {
			return
		}
	})

	t.Run("TestPortUnavailable", func(t *testing.T) {
		// 临时监听端口，使其变为不可用
		listener, err := net.Listen("tcp", "127.0.0.1:8081")
		if err != nil {
			log.Fatal("Listen error: ", err)
		}
		defer listener.Close()

		server := startTestCheckPortServer()
		defer server.Close()
		// 将服务器的URL更换为ws协议，构建WebSocket连接URL
		wsURL := "ws" + server.URL[len("http"):]

		u, err := url.Parse(wsURL)
		assert.NoError(t, err)
		u.RawQuery = "port=8081"
		// 创建连接WebSocket的客户端
		header := http.Header{}
		conn, resp, _ := websocket.DefaultDialer.Dial(u.String(), header)
		defer resp.Body.Close()
		defer conn.Close()

		messageType, _, err := conn.ReadMessage()
		if err != nil {
			return
		}
		if messageType == websocket.CloseMessage {
			return
		}
	})
}

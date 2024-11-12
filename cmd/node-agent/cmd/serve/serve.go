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

package serve

import (
	"crypto/tls"
	"errors"
	"net/http"
	"time"

	"github.com/spf13/cobra"
	"github.com/spf13/viper"

	"github.com/kosmos.io/kubenest/pkg/auth"
	"github.com/kosmos.io/kubenest/pkg/handlers"
	"github.com/kosmos.io/kubenest/pkg/logger"
)

var (
	certFile string // SSL certificate file
	keyFile  string // SSL key file
	addr     string // server listen address
	log      = logger.GetLogger()
)

// Cmd ServeCmd represents the serve command
var Cmd = &cobra.Command{
	Use:   "serve",
	Short: "Start a WebSocket server",
	RunE: func(_ *cobra.Command, _ []string) error {
		user := viper.GetString("WEB_USER")
		password := viper.GetString("WEB_PASS")
		port := viper.GetString("WEB_PORT")
		if len(user) == 0 || len(password) == 0 {
			log.Errorf("-user and -password are required %s %s", user, password)
			return errors.New("-user and -password are required")
		}
		if port != "" {
			addr = ":" + port
		}
		return start(addr, certFile, keyFile, user, password)
	},
}

func start(addr, certFile, keyFile, user, password string) error {
	mux := http.NewServeMux()
	// WebSocket endpoints with authentication
	mux.Handle("/upload", auth.NewAuthHandler(handlers.NewUploadHandler(), user, password))
	mux.Handle("/cmd", auth.NewAuthHandler(handlers.NewCmdHandler(), user, password))
	mux.Handle("/py", auth.NewAuthHandler(handlers.NewPythonHandler(), user, password))
	mux.Handle("/sh", auth.NewAuthHandler(handlers.NewShellHandler(), user, password))
	mux.Handle("/tty", auth.NewAuthHandler(handlers.NewTTYHandler(), user, password))
	mux.Handle("/check", auth.NewAuthHandler(handlers.NewCheckPortHandler(), user, password))

	// Health check and readiness routes don't require auth.
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	mux.HandleFunc("/readyz", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	})

	log.Infof("Starting server on %s", addr)
	tlsConfig := &tls.Config{MinVersion: tls.VersionTLS13}
	tlsConfig.Certificates = make([]tls.Certificate, 1)
	tlsConfig.Certificates[0], _ = tls.LoadX509KeyPair(certFile, keyFile)

	server := &http.Server{
		Addr:              addr,
		TLSConfig:         tlsConfig,
		Handler:           mux,
		ReadHeaderTimeout: 10 * time.Second,
	}
	err := server.ListenAndServeTLS("", "")
	if err != nil {
		log.Errorf("failed to start server: %v", err)
	}
	return err
}

func init() {
	// setup flags
	Cmd.PersistentFlags().StringVarP(&addr, "addr", "a", ":5678", "websocket service address")
	Cmd.PersistentFlags().StringVarP(&certFile, "cert", "c", "cert.pem", "SSL certificate file")
	Cmd.PersistentFlags().StringVarP(&keyFile, "key", "k", "key.pem", "SSL key file")
}

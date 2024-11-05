//go:build !test

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

package logger

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"runtime"

	"github.com/sirupsen/logrus"
)

var Log *logrus.Logger

func init() {
	defaultLogger := logrus.New()
	defaultLogger.SetReportCaller(true)
	defaultLogger.SetFormatter(&logrus.TextFormatter{
		FullTimestamp: true,
		CallerPrettyfier: func(f *runtime.Frame) (string, string) {
			filename := filepath.Base(f.File)
			return fmt.Sprintf("%s()", f.Function), fmt.Sprintf("%s:%d", filename, f.Line)
		},
	})
	defaultLogger.Out = os.Stdout
	logFile, err := os.OpenFile("app.log", os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0666)
	if err == nil {
		defaultLogger.SetOutput(io.MultiWriter(os.Stdout, logFile))
	} else {
		defaultLogger.Infof("Failed to log to file, using default stderr")
	}
	defaultLogger.SetLevel(logrus.InfoLevel)
	Log = defaultLogger
}

func GetLogger() *logrus.Logger {
	return Log
}

//go:build test
// +build test

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
	"os"

	"github.com/sirupsen/logrus"
)

var Log *logrus.Logger

func init() {
	mockLogger := logrus.New()
	mockLogger.Out = os.Stdout
	mockLogger.SetLevel(logrus.DebugLevel)
	Log = mockLogger
}

func GetLogger() *logrus.Logger {
	return Log
}

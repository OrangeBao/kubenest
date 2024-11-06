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

package cmd

import (
	"os"

	"github.com/spf13/cobra"
	"github.com/spf13/viper"

	"github.com/kosmos.io/kubenest/cmd/node-agent/cmd/serve"
	"github.com/kosmos.io/kubenest/pkg/logger"
)

var (
	user     string // username for authentication
	password string // password for authentication
	log      = logger.GetLogger()
)

// RootCmd represents the base command when called without any subcommands
var RootCmd = &cobra.Command{
	Use:   "kubenest node-agent server",
	Short: "node-agent is a tool for node to start websocket server",
	Long:  `node-agent serve for start websocket server to receive message from client and download file from client`,
	Run: func(cmd *cobra.Command, _ []string) {
		_ = cmd.Help()
	},
}

// Execute adds all child commands to the root command and sets flags appropriately.
// This is called by main.main(). It only needs to happen once to the rootCmd.
func Execute() {
	err := RootCmd.Execute()
	if err != nil {
		os.Exit(1)
	}
}

func init() {
	cobra.OnInitialize(initConfig)

	RootCmd.PersistentFlags().StringVarP(&user, "user", "u", "", "Username for authentication")
	RootCmd.PersistentFlags().StringVarP(&password, "password", "p", "", "Password for authentication")
	// bind flags to viper
	err := viper.BindPFlag("WEB_USER", RootCmd.PersistentFlags().Lookup("user"))
	if err != nil {
		log.Fatal(err)
	}
	err = viper.BindPFlag("WEB_PASS", RootCmd.PersistentFlags().Lookup("password"))
	if err != nil {
		log.Fatal(err)
	}
	// bind environment variables
	err = viper.BindEnv("WEB_USER", "WEB_USER")
	if err != nil {
		log.Fatal(err)
	}
	err = viper.BindEnv("WEB_PASS", "WEB_PASS")
	if err != nil {
		log.Fatal(err)
	}
	RootCmd.AddCommand(serve.Cmd)
}

func initConfig() {
	// Tell Viper to automatically look for a .env file
	viper.SetConfigFile("agent.env")
	currentDir, _ := os.Getwd()
	viper.AddConfigPath(currentDir)
	viper.AddConfigPath("/srv/node-agent/agent.env")
	viper.SetConfigType("toml")
	// If a agent.env file is found, read it in.
	if err := viper.ReadInConfig(); err != nil {
		log.Warnf("Load config file error, %s", err)
	}
	// set default value from agent.env
	if len(user) == 0 {
		user = viper.GetString("WEB_USER")
	}
	if len(password) == 0 {
		password = viper.GetString("WEB_PASS")
	}
}

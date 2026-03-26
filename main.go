package main

import (
	"encoding/json"
	"fmt"
	"os"
	"time"
	"github.com/go-ping/ping"
)

type Config struct {
	IPAddresses  []string `json:"target_ip_addresses"`
	IntervalSecs int      `json:"interval_seconds"`
}

func ReadConfig() Config {
	file, err := os.ReadFile("config.json")
	if err != nil {
		panic(err)
	}

	var config Config
	err = json.Unmarshal(file, &config)
	if err != nil {
		panic(err)
	}
	return config

}

func Ping(config Config) {
	for i, ip := range config.IPAddresses {
		fmt.Printf("IP %d: %s\n", i+1, ip)

		pinger, err := ping.NewPinger(ip)
		if err != nil {
			panic(err)
		}

		pinger.Count = 3
		pinger.Run()
		stats := pinger.Statistics()
		fmt.Printf("%+v\n", stats)
	}
}

func ReadTime(config Config) time.Duration {
	return time.Duration(config.IntervalSecs) * time.Second
}

func Timer(sec time.Duration, config Config) {
	ticker := time.NewTicker(sec)
	defer ticker.Stop()

	for range ticker.C {
		Ping(config)
	}
}

func main() {

	config := ReadConfig()
	sec := ReadTime(config)
	Ping(config)
	Timer(sec, config)
}

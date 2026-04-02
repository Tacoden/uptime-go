package main

import (
	"encoding/json"
	"fmt"
	"os"
	"time"

	"github.com/cheatsnake/gtl"

	probing "github.com/prometheus-community/pro-bing"
)

type Config struct {
	IPAddresses                   []string `json:"target_ip_addresses"`
	IntervalSecs                  int      `json:"interval_seconds"`
	Cooldown                      int      `json:"cooldown"`
	ResumeNotificationsAfterHours int      `json:"resumenotificationsafterhours"`
	ChatToken                     string   `json:"Bot_Token"`
	ChatId                        string   `json:"Chat_Id"`
}

var pingRunFailNotificationsSent int
var pingRunFailNotificationsResumeAt time.Time

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

func SendTelegram(config Config, message string, level bool) {
	if config.ChatToken == "" || config.ChatId == "" {
		fmt.Println("Telegram is not configured: missing Bot_Token or Chat_Id")
		return
	}

	logger, err := gtl.New(config.ChatToken, gtl.Options{
		ChatID: config.ChatId,
	})
	if err != nil {
		fmt.Printf("Telegram setup failed: %v\n", err)
		return
	}
	if level {
		logger.Err(message)
		return
	}
	logger.Ok(message)
}

func TelegramBot(config Config) {
	SendTelegram(config, "Hi, I've been set up to let you know if one of your servers go down!", false)
}

func ShouldSendPingRunFailedNotification(config Config) bool {
	if config.Cooldown <= 0 {
		return true
	}

	if !pingRunFailNotificationsResumeAt.IsZero() && time.Now().Before(pingRunFailNotificationsResumeAt) {
		return false
	}

	if !pingRunFailNotificationsResumeAt.IsZero() && !time.Now().Before(pingRunFailNotificationsResumeAt) {
		pingRunFailNotificationsSent = 0
		pingRunFailNotificationsResumeAt = time.Time{}
	}

	if pingRunFailNotificationsSent < config.Cooldown {
		pingRunFailNotificationsSent++
		if pingRunFailNotificationsSent >= config.Cooldown && config.ResumeNotificationsAfterHours > 0 {
			pingRunFailNotificationsResumeAt = time.Now().Add(time.Duration(config.ResumeNotificationsAfterHours) * time.Hour)
		}
		return true
	}

	if config.ResumeNotificationsAfterHours > 0 && pingRunFailNotificationsResumeAt.IsZero() {
		pingRunFailNotificationsResumeAt = time.Now().Add(time.Duration(config.ResumeNotificationsAfterHours) * time.Hour)
	}

	return false
}

func Ping(config Config) {
	for i, ip := range config.IPAddresses {
		fmt.Printf("IP %d: %s\n", i+1, ip)

		pinger, err := probing.NewPinger(ip)
		if err != nil {
			msg := fmt.Sprintf("Ping setup failed for %s: \n%v", ip, err)
			fmt.Println(msg)
			SendTelegram(config, msg, true)
			continue
		}

		// Use privileged ICMP mode so Linux file capabilities (CAP_NET_RAW) apply.
		pinger.SetPrivileged(true)

		pinger.Count = 3
		if err := pinger.Run(); err != nil {
			msg := fmt.Sprintf("Ping run failed for %s: \n%v", ip, err)
			fmt.Println(msg)
			if ShouldSendPingRunFailedNotification(config) {
				SendTelegram(config, msg, true)
			} else {
				fmt.Println("Ping run failure notification suppressed by cooldown/resume settings")
			}
			continue
		}
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
	TelegramBot(config)
	Ping(config)
	Timer(sec, config)
}

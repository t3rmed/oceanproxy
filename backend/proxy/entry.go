package proxy

import (
	"fmt"
	"time"

	"oceanproxy-api/config"
)

type Entry struct {
	PlanID    string `json:"plan_id"`
	Username  string `json:"username"`
	Password  string `json:"password"`
	AuthHost  string `json:"auth_host"`
	LocalHost string `json:"local_host"`
	AuthPort  int    `json:"auth_port"`
	LocalPort int    `json:"local_port"`
	Subdomain string `json:"subdomain"`
	ExpiresAt int64  `json:"expires_at"`
	CreatedAt int64  `json:"created_at"`
}

func NewEntry(planID, user, pass, upstreamHost string, port int, subdomain string, authPort int, expires int64) Entry {
	return Entry{
		PlanID:    planID,
		Username:  user,
		Password:  pass,
		AuthHost:  upstreamHost,
		LocalHost: fmt.Sprintf("%s.%s", subdomain, config.BaseDomain),
		AuthPort:  authPort,
		LocalPort: port,
		Subdomain: subdomain,
		ExpiresAt: expires,
		CreatedAt: time.Now().Unix(),
	}
}

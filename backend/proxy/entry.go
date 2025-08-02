package proxy

import (
	"fmt"
	"time"

	"oceanproxy-api/config"
)

type Entry struct {
	PlanID     string `json:"plan_id"`
	Username   string `json:"username"`
	Password   string `json:"password"`
	AuthHost   string `json:"auth_host"`
	LocalHost  string `json:"local_host"`
	AuthPort   int    `json:"auth_port"`
	LocalPort  int    `json:"local_port"`
	PublicPort int    `json:"public_port"`
	Subdomain  string `json:"subdomain"`
	ExpiresAt  int64  `json:"expires_at"`
	CreatedAt  int64  `json:"created_at"`
}

func NewEntry(planID, user, pass, upstreamHost string, publicPort int, subdomain string, authPort int, expires int64) Entry {
	// Assign local ports based on subdomain
	localPortMap := map[string]int{
		"usa":        10000,
		"eu":         20000,
		"alpha":      30000,
		"beta":       40000,
		"mobile":     50000,
		"unlim":      60000,
		"datacenter": 70000,
	}

	basePort := localPortMap[subdomain]
	if basePort == 0 {
		basePort = 10000 // fallback
	}

	return Entry{
		PlanID:     planID,
		Username:   user,
		Password:   pass,
		AuthHost:   upstreamHost,
		LocalHost:  fmt.Sprintf("%s.%s", subdomain, config.BaseDomain),
		AuthPort:   authPort,
		LocalPort:  basePort,
		PublicPort: publicPort,
		Subdomain:  subdomain,
		ExpiresAt:  expires,
		CreatedAt:  time.Now().Unix(),
	}
}

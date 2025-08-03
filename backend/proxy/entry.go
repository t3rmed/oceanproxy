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
	// Assign local ports based on subdomain (matching script port ranges)
	localPortMap := map[string]int{
		"usa":        10000, // Range: 10000-11999
		"eu":         12000, // Range: 12000-13999
		"alpha":      14000, // Range: 14000-15999
		"beta":       16000, // Range: 16000-17999
		"mobile":     18000, // Range: 18000-19999
		"unlim":      20000, // Range: 20000-21999
		"datacenter": 22000, // Range: 22000-23999
		"gamma":      24000, // Range: 24000-25999
		"delta":      26000, // Range: 26000-27999
		"epsilon":    28000, // Range: 28000-29999
		"zeta":       30000, // Range: 30000-31999
		"eta":        32000, // Range: 32000-33999
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

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
	// Get next available port for this subdomain
	localPort, err := GetNextAvailablePort(subdomain)
	if err != nil {
		// Fallback to base port if port manager fails
		localPortMap := map[string]int{
			"usa":        10000,
			"eu":         12000,
			"alpha":      14000,
			"beta":       16000,
			"mobile":     18000,
			"unlim":      20000,
			"datacenter": 22000,
			"gamma":      24000,
			"delta":      26000,
			"epsilon":    28000,
			"zeta":       30000,
			"eta":        32000,
		}
		localPort = localPortMap[subdomain]
		if localPort == 0 {
			localPort = 10000 // ultimate fallback
		}
	}

	return Entry{
		PlanID:     planID,
		Username:   user,
		Password:   pass,
		AuthHost:   upstreamHost,
		LocalHost:  fmt.Sprintf("%s.%s", subdomain, config.BaseDomain),
		AuthPort:   authPort,
		LocalPort:  localPort,
		PublicPort: publicPort,
		Subdomain:  subdomain,
		ExpiresAt:  expires,
		CreatedAt:  time.Now().Unix(),
	}
}

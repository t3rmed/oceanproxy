package handlers

import (
	"log"
	"os/exec"
)

func updateNginxUpstreams() {
	if err := exec.Command("/opt/oceanproxy/scripts/update_nginx_upstreams.sh").Run(); err != nil {
		log.Printf("⚠️ Warning: Failed to update nginx upstreams: %v", err)
	} else {
		log.Printf("✅ nginx upstreams updated successfully")
	}
}

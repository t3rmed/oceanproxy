package proxy

import (
	"fmt"
	"log"
	"os"
	"os/exec"
	"strconv"
)

func KillPort(port int) error {
	cmd := exec.Command("bash", "-c", "lsof -ti tcp:"+strconv.Itoa(port)+" | xargs -r kill -9")
	return cmd.Run()
}

func Spawn3proxy(e Entry) error {
	script := "../scripts/create_proxy_plan.sh"

	// sanity check: does the script exist?
	if _, err := os.Stat(script); os.IsNotExist(err) {
		log.Printf("❌ Spawn failed: script not found at %s", script)
		return fmt.Errorf("script not found: %s", script)
	}

	log.Printf("🚀 Spawning proxy: PlanID=%s | Port=%d | Subdomain=%s | Upstream=%s:%d",
		e.PlanID, e.LocalPort, e.Subdomain, e.AuthHost, e.AuthPort)

	cmd := exec.Command("bash", script,
		e.PlanID,
		fmt.Sprintf("%d", e.LocalPort),
		e.Username,
		e.Password,
		e.AuthHost,
		fmt.Sprintf("%d", e.AuthPort),
		e.Subdomain,
	)

	out, err := cmd.CombinedOutput()
	if err != nil {
		log.Printf("❌ Failed to spawn proxy for PlanID=%s Port=%d\nError: %v\nOutput:\n%s",
			e.PlanID, e.LocalPort, err, out)
		return err
	}

	log.Printf("✅ Proxy started on port %d for PlanID=%s", e.LocalPort, e.PlanID)
	return nil
}

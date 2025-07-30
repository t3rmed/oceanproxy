package proxy

import (
	"fmt"
	"log"
	"os/exec"
	"strconv"
)

func KillPort(port int) error {
	cmd := exec.Command("bash", "-c", "lsof -ti tcp:"+strconv.Itoa(port)+" | xargs -r kill -9")
	return cmd.Run()
}

func Spawn3proxy(e Entry) error {
	cmd := exec.Command("bash", "/root/oceanproxy-api/backend/scripts/create_proxy_plan.sh",
		e.PlanID, fmt.Sprintf("%d", e.LocalPort), e.Username, e.Password, e.AuthHost, fmt.Sprintf("%d", e.AuthPort))
	out, err := cmd.CombinedOutput()
	log.Printf("🛠️  Spawn output: %s", out)
	if err != nil {
		log.Printf("❌ Spawn error: %v", err)
	}
	return err
}

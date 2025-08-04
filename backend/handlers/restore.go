package handlers

import (
	"encoding/json"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"os/exec"
	"time"

	"oceanproxy-api/proxy"
)

// portInUse checks if a local TCP port is already bound
func portInUse(port int) bool {
	addr := fmt.Sprintf("127.0.0.1:%d", port)
	conn, err := net.DialTimeout("tcp", addr, 1*time.Second)
	if err != nil {
		return false // not in use
	}
	_ = conn.Close()
	return true // already bound
}

func RestoreHandler(w http.ResponseWriter, r *http.Request) {
	data, err := os.ReadFile(proxy.LogPath)
	if err != nil {
		http.Error(w, fmt.Sprintf("Failed to read proxy log: %v", err), http.StatusInternalServerError)
		return
	}

	var entries []proxy.Entry
	if err := json.Unmarshal(data, &entries); err != nil {
		http.Error(w, fmt.Sprintf("Failed to parse proxy log: %v", err), http.StatusInternalServerError)
		return
	}

	existing := make(map[string]map[string]bool)
	for _, e := range entries {
		if existing[e.PlanID] == nil {
			existing[e.PlanID] = make(map[string]bool)
		}
		existing[e.PlanID][e.Subdomain] = true
	}

	var restored, failed []string
	var newEntries []proxy.Entry

	for _, e := range entries {
		if e.ExpiresAt < time.Now().Unix() {
			continue // skip expired proxies
		}

		// If the port is in use, assume it's stale and force kill it
		if portInUse(e.LocalPort) {
			if err := proxy.KillPort(e.LocalPort); err != nil {
				failed = append(failed, e.PlanID+"-"+e.Subdomain+" (kill failed)")
				continue
			}
			time.Sleep(1 * time.Second) // brief pause after killing
		}

		// Attempt to start 3proxy for this entry
		err := proxy.Spawn3proxy(e)
		if err != nil {
			failed = append(failed, e.PlanID+"-"+e.Subdomain)
		} else {
			restored = append(restored, e.PlanID+"-"+e.Subdomain)
		}

		// Check and restore missing counterpart region (EU/USA)
		if e.Subdomain == "eu" && !existing[e.PlanID]["usa"] {
			usaEntry := proxy.NewEntry(e.PlanID, e.Username, e.Password, "pr-us.proxies.fo", 1337, "usa", e.AuthPort, e.ExpiresAt)
			if portInUse(usaEntry.LocalPort) {
				_ = proxy.KillPort(usaEntry.LocalPort)
			}
			if err := proxy.Spawn3proxy(usaEntry); err == nil {
				newEntries = append(newEntries, usaEntry)
				restored = append(restored, e.PlanID+"-usa")
			} else {
				failed = append(failed, e.PlanID+"-usa")
			}
		}

		if e.Subdomain == "usa" && !existing[e.PlanID]["eu"] {
			euEntry := proxy.NewEntry(e.PlanID, e.Username, e.Password, "pr-eu.proxies.fo", 1338, "eu", e.AuthPort, e.ExpiresAt)
			if portInUse(euEntry.LocalPort) {
				_ = proxy.KillPort(euEntry.LocalPort)
			}
			if err := proxy.Spawn3proxy(euEntry); err == nil {
				newEntries = append(newEntries, euEntry)
				restored = append(restored, e.PlanID+"-eu")
			} else {
				failed = append(failed, e.PlanID+"-eu")
			}
		}
	}

	if len(newEntries) > 0 {
		entries = append(entries, newEntries...)
		_ = proxy.SaveProxyLog(entries)
	}

	// Update nginx upstreams after restore
	if len(restored) > 0 {
		if err := exec.Command("/opt/oceanproxy/scripts/update_nginx_upstreams.sh").Run(); err != nil {
			log.Printf("⚠️ Warning: Failed to update nginx upstreams after restore: %v", err)
		} else {
			log.Printf("✅ nginx upstreams updated successfully after restore")
		}
	}

	JSON(w, map[string]interface{}{
		"restored": restored,
		"failed":   failed,
	})
}

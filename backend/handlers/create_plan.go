package handlers

import (
	"fmt"
	"log"
	"net/http"
	"os/exec"

	"oceanproxy-api/providers"
	"oceanproxy-api/proxy"
)

func CreateNettifyPlanHandler(w http.ResponseWriter, r *http.Request) {
	if err := r.ParseForm(); err != nil {
		http.Error(w, fmt.Sprintf("Invalid form data: %v", err), http.StatusBadRequest)
		return
	}

	proxyInfo, err := providers.CreateNettifyPlan(r.Form)
	if err != nil {
		http.Error(w, fmt.Sprintf("Failed to create plan: %v", err), http.StatusBadGateway)
		return
	}

	var proxies []string
	for _, p := range proxyInfo.Proxies {
		err := proxy.Spawn3proxy(p)
		if err != nil {
			http.Error(w, fmt.Sprintf("Failed to spawn proxy: %v", err), http.StatusInternalServerError)
			return
		}
		_ = proxy.LogProxy(p)

		// Update nginx upstreams after proxy is created and logged
		if err := exec.Command("/opt/oceanproxy/scripts/update_nginx_upstreams.sh").Run(); err != nil {
			log.Printf("⚠️ Warning: Failed to update nginx upstreams: %v", err)
		} else {
			log.Printf("✅ nginx upstreams updated successfully")
		}

		// Return the PUBLIC port, not the local port
		proxies = append(proxies, fmt.Sprintf("http://%s:%s@%s:%d", p.Username, p.Password, p.LocalHost, p.PublicPort))
	}

	JSON(w, map[string]interface{}{
		"success":    true,
		"plan_id":    proxyInfo.PlanID,
		"username":   proxyInfo.Username,
		"password":   proxyInfo.Password,
		"expires_at": proxyInfo.ExpiresAt,
		"proxies":    proxies,
	})
}

func CreatePlanHandler(w http.ResponseWriter, r *http.Request) {
	if err := r.ParseForm(); err != nil {
		http.Error(w, fmt.Sprintf("Invalid form data: %v", err), http.StatusBadRequest)
		return
	}

	proxyInfo, err := providers.CreateProxiesFOPlan(r.Form)
	if err != nil {
		http.Error(w, fmt.Sprintf("Failed to create plan: %v", err), http.StatusBadGateway)
		return
	}

	var proxies []string
	for _, p := range proxyInfo.Proxies {
		err := proxy.Spawn3proxy(p)
		if err != nil {
			http.Error(w, fmt.Sprintf("Failed to spawn proxy: %v", err), http.StatusInternalServerError)
			return
		}
		_ = proxy.LogProxy(p)

		// Update nginx upstreams after proxy is created and logged
		if err := exec.Command("/opt/oceanproxy/scripts/update_nginx_upstreams.sh").Run(); err != nil {
			log.Printf("⚠️ Warning: Failed to update nginx upstreams: %v", err)
		} else {
			log.Printf("✅ nginx upstreams updated successfully")
		}

		// Return the PUBLIC port, not the local port
		proxies = append(proxies, fmt.Sprintf("http://%s:%s@%s:%d", p.Username, p.Password, p.LocalHost, p.PublicPort))
	}

	JSON(w, map[string]interface{}{
		"success":    true,
		"plan_id":    proxyInfo.PlanID,
		"username":   proxyInfo.Username,
		"password":   proxyInfo.Password,
		"expires_at": proxyInfo.ExpiresAt,
		"proxies":    proxies,
	})
}

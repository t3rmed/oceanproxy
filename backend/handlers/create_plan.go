package handlers

import (
	"fmt"
	"net/http"

	"oceanproxy-api/providers"
	"oceanproxy-api/proxy"
)

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
		proxies = append(proxies, fmt.Sprintf("http://%s:%s@%s:%d", p.Username, p.Password, p.LocalHost, p.LocalPort))
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

package providers

import (
	"encoding/json"
	"errors"
	"net/http"
	"net/url"
	"strings"

	"oceanproxy-api/config"
	"oceanproxy-api/proxy"
)

type ProxyPlanInfo struct {
	PlanID    string
	Username  string
	Password  string
	ExpiresAt int64
	Proxies   []proxy.Entry
}

func CreateProxiesFOPlan(form url.Values) (*ProxyPlanInfo, error) {
	apiURL := "https://app.proxies.fo/api/plans/new"

	resellerMap := map[string]string{
		"residential": "7c9ea873-63f9-4013-9147-3807cc6f0553",
		"isp":         "3471aa35-7922-488a-a7a9-b92a5510080e",
		"datacenter":  "b3fd0f3c-693d-4ec5-b49f-c77feaab0b72",
	}
	reseller := form.Get("reseller")
	resellerID, ok := resellerMap[reseller]
	if !ok {
		return nil, errors.New("invalid reseller type")
	}

	// Defaults
	if reseller == "datacenter" {
		if form.Get("duration") == "" {
			form.Set("duration", "1")
		}
		if form.Get("threads") == "" {
			form.Set("threads", "500")
		}
	} else {
		form.Set("duration", "180")
		if form.Get("bandwidth") == "" {
			form.Set("bandwidth", "1")
		}
	}
	form.Set("reseller", resellerID)

	req, _ := http.NewRequest("POST", apiURL, strings.NewReader(form.Encode()))
	req.Header.Set("X-Api-Auth", config.APIKey)
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	var result map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, err
	}

	data := result["Data"].(map[string]interface{})

	user := data["AuthUsername"].(string)
	pass := data["AuthPassword"].(string)
	planID := data["ID"].(string)
	authPort := int(data["AuthPort"].(float64))
	expires := int64(data["EndsDate"].(float64))

	proxies := []proxy.Entry{
		proxy.NewEntry(planID, user, pass, "pr-eu.proxies.fo", 1338, "eu", authPort, expires),
		proxy.NewEntry(planID, user, pass, "pr-us.proxies.fo", 1337, "usa", authPort, expires),
	}

	return &ProxyPlanInfo{
		PlanID:    planID,
		Username:  user,
		Password:  pass,
		ExpiresAt: expires,
		Proxies:   proxies,
	}, nil
}

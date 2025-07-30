package providers

import (
	"bytes"
	"encoding/json"
	"errors"
	"net/http"
	"net/url"
	"strconv"

	"oceanproxy-api/config"
	"oceanproxy-api/proxy"
)

type NettifyPlanInfo struct {
	PlanID    string
	Username  string
	Password  string
	ExpiresAt int64
	Proxies   []proxy.Entry
}

func CreateNettifyPlan(form url.Values) (*NettifyPlanInfo, error) {
	apiURL := "https://api.nettify.xyz/plans/create"

	planType := form.Get("plan_type")
	if planType == "" {
		planType = "residential"
	}

	username := form.Get("username")
	if username == "" {
		return nil, errors.New("username is required")
	}

	password := form.Get("password")
	if password == "" {
		return nil, errors.New("password is required")
	}

	// Defaults
	var requestData map[string]interface{}

	if planType == "unlimited" {
		hours := form.Get("hours")
		if hours == "" {
			hours = "1" // default to 1 hour
		}
		hoursInt, _ := strconv.Atoi(hours)

		requestData = map[string]interface{}{
			"username":       username,
			"password":       password,
			"plan_type":      planType,
			"duration_hours": hoursInt,
		}
	} else {
		if form.Get("bandwidth") == "" {
			form.Set("bandwidth", "1")
		}
		bandwidth, _ := strconv.ParseFloat(form.Get("bandwidth"), 64)
		bandwidthMB := int(bandwidth * 1024) // Convert GB to MB

		requestData = map[string]interface{}{
			"username":     username,
			"password":     password,
			"plan_type":    planType,
			"bandwidth_mb": bandwidthMB,
		}
	}

	jsonData, _ := json.Marshal(requestData)
	req, _ := http.NewRequest("POST", apiURL, bytes.NewBuffer(jsonData))
	req.Header.Set("Authorization", "Bearer "+config.APIKey)
	req.Header.Set("Content-Type", "application/json")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	var result map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, err
	}

	user := result["username"].(string)
	planID := result["plan_id"].(string)

	// Get plan details to get password
	detailsURL := "https://api.nettify.xyz/plans/" + planID
	detailsReq, _ := http.NewRequest("GET", detailsURL, nil)
	detailsReq.Header.Set("Authorization", "Bearer "+config.APIKey)

	detailsResp, err := http.DefaultClient.Do(detailsReq)
	if err != nil {
		return nil, err
	}
	defer detailsResp.Body.Close()

	var details map[string]interface{}
	if err := json.NewDecoder(detailsResp.Body).Decode(&details); err != nil {
		return nil, err
	}

	pass := details["password"].(string)
	expires := int64(0) // No expiration for bandwidth-based plans

	var proxies []proxy.Entry

	switch planType {
	case "residential":
		proxies = []proxy.Entry{
			proxy.NewEntry(planID, user, pass, "alpha.oceanproxy.io", 9876, "global", 9876, expires),
		}
	case "datacenter":
		proxies = []proxy.Entry{
			proxy.NewEntry(planID, user, pass, "beta.oceanproxy.io", 8765, "global", 8765, expires),
		}
	case "mobile":
		proxies = []proxy.Entry{
			proxy.NewEntry(planID, user, pass, "mobile.oceanproxy.io", 7654, "global", 7654, expires),
		}
	case "unlimited":
		proxies = []proxy.Entry{
			proxy.NewEntry(planID, user, pass, "unlim.oceanproxy.io", 6543, "global", 6543, expires),
		}
	}

	return &NettifyPlanInfo{
		PlanID:    planID,
		Username:  user,
		Password:  pass,
		ExpiresAt: expires,
		Proxies:   proxies,
	}, nil
}

// handlers/monitoring.go
package handlers

import (
	"encoding/json"
	"fmt"
	"html/template"
	"io"
	"net"
	"net/http"
	"os"
	"os/exec"
	"runtime"
	"strconv"
	"strings"
	"time"

	"oceanproxy-api/config"
	"oceanproxy-api/proxy"
)

var startTime = time.Now()

type SystemStats struct {
	CPUCores      int     `json:"cpu_cores"`
	CPUUsage      float64 `json:"cpu_usage"`
	MemoryTotal   uint64  `json:"memory_total"`
	MemoryUsed    uint64  `json:"memory_used"`
	MemoryPercent float64 `json:"memory_percent"`
	DiskTotal     uint64  `json:"disk_total"`
	DiskUsed      uint64  `json:"disk_used"`
	DiskPercent   float64 `json:"disk_percent"`
	LoadAverage   string  `json:"load_average"`
	Uptime        string  `json:"uptime"`
	UptimeSeconds int64   `json:"uptime_seconds"`
}

type ProxyStats struct {
	TotalPlans     int                      `json:"total_plans"`
	ActiveProxies  int                      `json:"active_proxies"`
	ExpiredProxies int                      `json:"expired_proxies"`
	ProxiesByType  map[string]int           `json:"proxies_by_type"`
	PortUsage      map[string]PortUsageInfo `json:"port_usage"`
	RecentProxies  []proxy.Entry            `json:"recent_proxies"`
}

type PortUsageInfo struct {
	Used       int     `json:"used"`
	Total      int     `json:"total"`
	Percentage float64 `json:"percentage"`
	Available  int     `json:"available"`
}

type NetworkStats struct {
	OpenPorts       []PortInfo              `json:"open_ports"`
	SubdomainStatus map[string]DomainStatus `json:"subdomain_status"`
	ServerIP        string                  `json:"server_ip"`
}

type PortInfo struct {
	Port    int    `json:"port"`
	Service string `json:"service"`
	Status  string `json:"status"`
}

type DomainStatus struct {
	Subdomain   string `json:"subdomain"`
	Port        int    `json:"port"`
	Resolves    bool   `json:"resolves"`
	ResolvedIP  string `json:"resolved_ip"`
	IsListening bool   `json:"is_listening"`
}

type MonitoringData struct {
	System      SystemStats  `json:"system"`
	Proxies     ProxyStats   `json:"proxies"`
	Network     NetworkStats `json:"network"`
	LastUpdated time.Time    `json:"last_updated"`
}

// MonitoringAPIHandler returns JSON monitoring data
func MonitoringAPIHandler(w http.ResponseWriter, r *http.Request) {
	// Check for bearer token in query parameter for web access
	token := r.URL.Query().Get("token")
	if token == "" {
		// Check Authorization header
		authHeader := r.Header.Get("Authorization")
		if authHeader != "" {
			token = strings.TrimPrefix(authHeader, "Bearer ")
		}
	}

	if token != config.BearerToken {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	data := collectMonitoringData()
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(data)
}

// MonitoringPanelHandler serves the HTML monitoring dashboard
func MonitoringPanelHandler(w http.ResponseWriter, r *http.Request) {
	// Check for bearer token in query parameter for web access
	token := r.URL.Query().Get("token")
	if token == "" {
		// Check Authorization header
		authHeader := r.Header.Get("Authorization")
		if authHeader != "" {
			token = strings.TrimPrefix(authHeader, "Bearer ")
		}
	}

	if token != config.BearerToken {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	// Serve the monitoring HTML
	w.Header().Set("Content-Type", "text/html; charset=utf-8")

	templateData := map[string]interface{}{
		"Token":   token,
		"Domain":  config.BaseDomain,
		"ApiPort": os.Getenv("PORT"),
	}

	if err := monitoringHTML.Execute(w, templateData); err != nil {
		http.Error(w, fmt.Sprintf("Template execution error: %v", err), http.StatusInternalServerError)
		return
	}
}

func collectMonitoringData() MonitoringData {
	return MonitoringData{
		System:      getSystemStats(),
		Proxies:     getProxyStats(),
		Network:     getNetworkStats(),
		LastUpdated: time.Now(),
	}
}

func getSystemStats() SystemStats {
	stats := SystemStats{
		CPUCores: runtime.NumCPU(),
	}

	// Get CPU usage
	if output, err := exec.Command("bash", "-c", "top -bn1 | grep 'Cpu(s)' | awk '{print $2}' | cut -d'%' -f1").Output(); err == nil {
		if cpu, err := strconv.ParseFloat(strings.TrimSpace(string(output)), 64); err == nil {
			stats.CPUUsage = cpu
		}
	}

	// Get memory info
	if output, err := exec.Command("free", "-b").Output(); err == nil {
		lines := strings.Split(string(output), "\n")
		if len(lines) > 1 {
			fields := strings.Fields(lines[1])
			if len(fields) >= 3 {
				if total, err := strconv.ParseUint(fields[1], 10, 64); err == nil {
					stats.MemoryTotal = total
				}
				if used, err := strconv.ParseUint(fields[2], 10, 64); err == nil {
					stats.MemoryUsed = used
				}
			}
		}
	}
	if stats.MemoryTotal > 0 {
		stats.MemoryPercent = float64(stats.MemoryUsed) / float64(stats.MemoryTotal) * 100
	}

	// Get disk usage
	if output, err := exec.Command("df", "-B1", "/").Output(); err == nil {
		lines := strings.Split(string(output), "\n")
		if len(lines) > 1 {
			fields := strings.Fields(lines[1])
			if len(fields) >= 4 {
				if total, err := strconv.ParseUint(fields[1], 10, 64); err == nil {
					stats.DiskTotal = total
				}
				if used, err := strconv.ParseUint(fields[2], 10, 64); err == nil {
					stats.DiskUsed = used
				}
			}
		}
	}
	if stats.DiskTotal > 0 {
		stats.DiskPercent = float64(stats.DiskUsed) / float64(stats.DiskTotal) * 100
	}

	// Get load average
	if output, err := exec.Command("uptime").Output(); err == nil {
		if idx := strings.Index(string(output), "load average:"); idx != -1 {
			stats.LoadAverage = strings.TrimSpace(string(output)[idx+13:])
		}
	}

	// Calculate uptime
	uptime := time.Since(startTime)
	stats.UptimeSeconds = int64(uptime.Seconds())
	days := int(uptime.Hours() / 24)
	hours := int(uptime.Hours()) % 24
	minutes := int(uptime.Minutes()) % 60
	stats.Uptime = fmt.Sprintf("%dd %dh %dm", days, hours, minutes)

	return stats
}

func getProxyStats() ProxyStats {
	stats := ProxyStats{
		ProxiesByType: make(map[string]int),
		PortUsage:     make(map[string]PortUsageInfo),
	}

	// Read proxy log
	data, err := os.ReadFile(proxy.LogPath)
	if err != nil {
		return stats
	}

	var entries []proxy.Entry
	if err := json.Unmarshal(data, &entries); err != nil {
		return stats
	}

	stats.TotalPlans = len(entries)
	now := time.Now().Unix()

	// Port ranges for each subdomain
	portRanges := map[string]struct{ start, end int }{
		"usa":        {10000, 11999},
		"eu":         {12000, 13999},
		"alpha":      {14000, 15999},
		"beta":       {16000, 17999},
		"mobile":     {18000, 19999},
		"unlim":      {20000, 21999},
		"datacenter": {22000, 23999},
		"gamma":      {24000, 25999},
		"delta":      {26000, 27999},
		"epsilon":    {28000, 29999},
		"zeta":       {30000, 31999},
		"eta":        {32000, 33999},
	}

	// Initialize port usage
	for subdomain, portRange := range portRanges {
		stats.PortUsage[subdomain] = PortUsageInfo{
			Used:  0,
			Total: portRange.end - portRange.start + 1,
		}
	}

	// Analyze entries
	for _, entry := range entries {
		// Count by type
		stats.ProxiesByType[entry.Subdomain]++

		// Count port usage
		if usage, exists := stats.PortUsage[entry.Subdomain]; exists {
			usage.Used++
			usage.Available = usage.Total - usage.Used
			usage.Percentage = float64(usage.Used) / float64(usage.Total) * 100
			stats.PortUsage[entry.Subdomain] = usage
		}

		// Check if active or expired
		if entry.ExpiresAt == 0 || entry.ExpiresAt > now {
			stats.ActiveProxies++
		} else {
			stats.ExpiredProxies++
		}
	}

	// Get recent proxies (last 10)
	if len(entries) > 0 {
		start := 0
		if len(entries) > 10 {
			start = len(entries) - 10
		}
		stats.RecentProxies = entries[start:]
	}

	return stats
}

func getNetworkStats() NetworkStats {
	stats := NetworkStats{
		OpenPorts:       []PortInfo{},
		SubdomainStatus: make(map[string]DomainStatus),
	}

	// Get server IP
	if resp, err := http.Get("https://api.ipify.org"); err == nil {
		defer resp.Body.Close()
		if body, err := io.ReadAll(resp.Body); err == nil {
			stats.ServerIP = string(body)
		}
	}

	// Define proxy ports and their services
	proxyPorts := map[int]string{
		1337: "usa",
		1338: "eu",
		9876: "alpha",
		8765: "beta",
		7654: "mobile",
		6543: "unlim",
		1339: "datacenter",
		5432: "gamma",
		4321: "delta",
		3210: "epsilon",
		2109: "zeta",
		1098: "eta",
		9090: "api",
	}

	// Check open ports
	for port, service := range proxyPorts {
		status := "closed"
		if isPortOpen(port) {
			status = "open"
		}
		stats.OpenPorts = append(stats.OpenPorts, PortInfo{
			Port:    port,
			Service: service,
			Status:  status,
		})
	}

	// Check subdomain status
	subdomains := []string{"usa", "eu", "alpha", "beta", "mobile", "unlim", "datacenter",
		"gamma", "delta", "epsilon", "zeta", "eta", "api"}

	for _, subdomain := range subdomains {
		port := 80 // default
		if p, exists := reversePortMap()[subdomain]; exists {
			port = p
		}

		status := DomainStatus{
			Subdomain: subdomain,
			Port:      port,
		}

		// Check DNS resolution
		fullDomain := fmt.Sprintf("%s.%s", subdomain, config.BaseDomain)
		if ips, err := net.LookupHost(fullDomain); err == nil && len(ips) > 0 {
			status.Resolves = true
			status.ResolvedIP = ips[0]
		}

		// Check if port is listening
		status.IsListening = isPortOpen(port)

		stats.SubdomainStatus[subdomain] = status
	}

	return stats
}

func isPortOpen(port int) bool {
	conn, err := net.DialTimeout("tcp", fmt.Sprintf("127.0.0.1:%d", port), 1*time.Second)
	if err != nil {
		return false
	}
	conn.Close()
	return true
}

func reversePortMap() map[string]int {
	return map[string]int{
		"usa":        1337,
		"eu":         1338,
		"alpha":      9876,
		"beta":       8765,
		"mobile":     7654,
		"unlim":      6543,
		"datacenter": 1339,
		"gamma":      5432,
		"delta":      4321,
		"epsilon":    3210,
		"zeta":       2109,
		"eta":        1098,
		"api":        9090,
	}
}

// Monitoring HTML template
var monitoringHTML = template.Must(template.New("monitoring").Parse(`
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>OceanProxy Monitoring Panel</title>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&display=swap" rel="stylesheet">
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            font-family: 'Inter', -apple-system, BlinkMacSystemFont, sans-serif;
            background: #0a0e27;
            color: #e0e6ed;
            line-height: 1.6;
            overflow-x: hidden;
        }

        /* Animated background */
        body::before {
            content: '';
            position: fixed;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            background: 
                radial-gradient(circle at 20% 80%, rgba(0, 149, 255, 0.1) 0%, transparent 50%),
                radial-gradient(circle at 80% 20%, rgba(0, 255, 157, 0.1) 0%, transparent 50%),
                radial-gradient(circle at 40% 40%, rgba(147, 51, 234, 0.1) 0%, transparent 50%);
            animation: float 20s ease-in-out infinite;
            z-index: -1;
        }

        @keyframes float {
            0%, 100% { transform: translate(0, 0) rotate(0deg); }
            33% { transform: translate(-20px, -20px) rotate(1deg); }
            66% { transform: translate(20px, -10px) rotate(-1deg); }
        }

        .container {
            max-width: 1400px;
            margin: 0 auto;
            padding: 20px;
        }

        /* Header */
        .header {
            background: rgba(13, 17, 43, 0.8);
            backdrop-filter: blur(10px);
            border: 1px solid rgba(255, 255, 255, 0.1);
            border-radius: 16px;
            padding: 30px;
            margin-bottom: 30px;
            box-shadow: 0 8px 32px rgba(0, 0, 0, 0.3);
        }

        .header h1 {
            font-size: 2.5rem;
            font-weight: 700;
            background: linear-gradient(135deg, #0095ff 0%, #00ff9d 100%);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            margin-bottom: 10px;
        }

        .header .subtitle {
            color: #8892b0;
            font-size: 1.1rem;
        }

        /* Grid Layout */
        .grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }

        .grid-2 {
            grid-template-columns: repeat(auto-fit, minmax(600px, 1fr));
        }

        /* Cards */
        .card {
            background: rgba(13, 17, 43, 0.8);
            backdrop-filter: blur(10px);
            border: 1px solid rgba(255, 255, 255, 0.1);
            border-radius: 16px;
            padding: 25px;
            transition: all 0.3s ease;
            position: relative;
            overflow: hidden;
        }

        .card::before {
            content: '';
            position: absolute;
            top: 0;
            left: 0;
            right: 0;
            height: 2px;
            background: linear-gradient(90deg, #0095ff 0%, #00ff9d 100%);
            transform: translateX(-100%);
            transition: transform 0.6s ease;
        }

        .card:hover::before {
            transform: translateX(0);
        }

        .card:hover {
            transform: translateY(-5px);
            box-shadow: 0 12px 40px rgba(0, 0, 0, 0.4);
            border-color: rgba(0, 149, 255, 0.3);
        }

        .card h2 {
            font-size: 1.3rem;
            margin-bottom: 20px;
            color: #e0e6ed;
            display: flex;
            align-items: center;
            gap: 10px;
        }

        .card h2 .icon {
            width: 24px;
            height: 24px;
            display: inline-flex;
            align-items: center;
            justify-content: center;
        }

        /* Stats */
        .stat {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 12px 0;
            border-bottom: 1px solid rgba(255, 255, 255, 0.05);
        }

        .stat:last-child {
            border-bottom: none;
        }

        .stat-label {
            color: #8892b0;
            font-size: 0.9rem;
        }

        .stat-value {
            font-size: 1.1rem;
            font-weight: 600;
            color: #e0e6ed;
        }

        .stat-value.success { color: #00ff9d; }
        .stat-value.warning { color: #ffb800; }
        .stat-value.danger { color: #ff4757; }

        /* Progress Bars */
        .progress-container {
            margin-top: 10px;
        }

        .progress-bar {
            height: 8px;
            background: rgba(255, 255, 255, 0.1);
            border-radius: 4px;
            overflow: hidden;
            position: relative;
        }

        .progress-fill {
            height: 100%;
            background: linear-gradient(90deg, #0095ff 0%, #00ff9d 100%);
            border-radius: 4px;
            transition: width 0.6s ease;
            position: relative;
            overflow: hidden;
        }

        .progress-fill::after {
            content: '';
            position: absolute;
            top: 0;
            left: 0;
            bottom: 0;
            right: 0;
            background: linear-gradient(
                90deg,
                transparent,
                rgba(255, 255, 255, 0.3),
                transparent
            );
            animation: shimmer 2s infinite;
        }

        @keyframes shimmer {
            0% { transform: translateX(-100%); }
            100% { transform: translateX(100%); }
        }

        .progress-label {
            display: flex;
            justify-content: space-between;
            margin-bottom: 5px;
            font-size: 0.85rem;
        }

        /* Port Grid */
        .port-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(140px, 1fr));
            gap: 12px;
            margin-top: 15px;
        }

        .port-item {
            background: rgba(255, 255, 255, 0.05);
            border: 1px solid rgba(255, 255, 255, 0.1);
            border-radius: 8px;
            padding: 15px;
            text-align: center;
            transition: all 0.3s ease;
        }

        .port-item:hover {
            background: rgba(255, 255, 255, 0.08);
            transform: translateY(-2px);
        }

        .port-item.active {
            border-color: #00ff9d;
            background: rgba(0, 255, 157, 0.1);
        }

        .port-name {
            font-weight: 600;
            margin-bottom: 5px;
            text-transform: uppercase;
            font-size: 0.85rem;
        }

        .port-usage {
            font-size: 0.75rem;
            color: #8892b0;
        }

        .port-percent {
            font-size: 1.2rem;
            font-weight: 700;
            margin-top: 5px;
        }

        /* Domain Status */
        .domain-grid {
            display: grid;
            gap: 10px;
        }

        .domain-item {
            display: grid;
            grid-template-columns: 1fr auto auto;
            gap: 15px;
            align-items: center;
            padding: 12px;
            background: rgba(255, 255, 255, 0.05);
            border-radius: 8px;
            font-size: 0.9rem;
        }

        .domain-name {
            font-weight: 500;
        }

        .status-badge {
            padding: 4px 12px;
            border-radius: 20px;
            font-size: 0.75rem;
            font-weight: 600;
            text-transform: uppercase;
        }

        .status-badge.success {
            background: rgba(0, 255, 157, 0.2);
            color: #00ff9d;
            border: 1px solid rgba(0, 255, 157, 0.3);
        }

        .status-badge.danger {
            background: rgba(255, 71, 87, 0.2);
            color: #ff4757;
            border: 1px solid rgba(255, 71, 87, 0.3);
        }

        /* Recent Proxies */
        .proxy-list {
            max-height: 400px;
            overflow-y: auto;
        }

        .proxy-item {
            background: rgba(255, 255, 255, 0.05);
            border-radius: 8px;
            padding: 15px;
            margin-bottom: 10px;
            display: grid;
            grid-template-columns: 1fr auto;
            gap: 10px;
            font-size: 0.9rem;
        }

        .proxy-info {
            display: grid;
            gap: 5px;
        }

        .proxy-username {
            font-weight: 600;
            color: #0095ff;
        }

        .proxy-details {
            color: #8892b0;
            font-size: 0.85rem;
        }

        /* Loading */
        .loading {
            display: flex;
            align-items: center;
            justify-content: center;
            height: 100px;
        }

        .spinner {
            width: 40px;
            height: 40px;
            border: 3px solid rgba(255, 255, 255, 0.1);
            border-top-color: #0095ff;
            border-radius: 50%;
            animation: spin 1s linear infinite;
        }

        @keyframes spin {
            to { transform: rotate(360deg); }
        }

        /* Responsive */
        @media (max-width: 768px) {
            .header h1 { font-size: 2rem; }
            .grid-2 { grid-template-columns: 1fr; }
            .port-grid { grid-template-columns: repeat(auto-fill, minmax(100px, 1fr)); }
        }

        /* Scrollbar */
        ::-webkit-scrollbar {
            width: 8px;
            height: 8px;
        }

        ::-webkit-scrollbar-track {
            background: rgba(255, 255, 255, 0.05);
            border-radius: 4px;
        }

        ::-webkit-scrollbar-thumb {
            background: rgba(255, 255, 255, 0.2);
            border-radius: 4px;
        }

        ::-webkit-scrollbar-thumb:hover {
            background: rgba(255, 255, 255, 0.3);
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🌊 OceanProxy Monitoring</h1>
            <div class="subtitle">Real-time system monitoring and analytics</div>
        </div>

        <div id="content">
            <div class="loading">
                <div class="spinner"></div>
            </div>
        </div>
    </div>

    <script>
        const token = '{{.Token}}';
        const apiUrl = '/monitoring/api';

        async function fetchData() {
            try {
                const response = await fetch(apiUrl, {
                    headers: {
                        'Authorization': 'Bearer ' + token
                    }
                });
                
                if (!response.ok) throw new Error('Failed to fetch data');
                
                const data = await response.json();
                updateDashboard(data);
            } catch (error) {
                console.error('Error fetching data:', error);
                document.getElementById('content').innerHTML = '<div class="card"><p>Error loading data. Please refresh.</p></div>';
            }
        }

        function formatBytes(bytes) {
            if (bytes === 0) return '0 B';
            const k = 1024;
            const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
            const i = Math.floor(Math.log(bytes) / Math.log(k));
            return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
        }

        function formatTimestamp(timestamp) {
            const date = new Date(timestamp);
            return date.toLocaleString();
        }

        function getStatusClass(percentage) {
            if (percentage < 50) return 'success';
            if (percentage < 80) return 'warning';
            return 'danger';
        }

        const baseDomain = '{{.Domain}}';
        
        function updateDashboard(data) {
            const html = ` + "`" + `
                <!-- System Stats -->
                <div class="grid">
                    <div class="card">
                        <h2>
                            <span class="icon">💻</span>
                            System Overview
                        </h2>
                        <div class="stat">
                            <span class="stat-label">Uptime</span>
                            <span class="stat-value success">${data.system.uptime}</span>
                        </div>
                        <div class="stat">
                            <span class="stat-label">CPU Cores</span>
                            <span class="stat-value">${data.system.cpu_cores}</span>
                        </div>
                        <div class="stat">
                            <span class="stat-label">CPU Usage</span>
                            <span class="stat-value ${getStatusClass(data.system.cpu_usage)}">${data.system.cpu_usage.toFixed(1)}%</span>
                        </div>
                        <div class="stat">
                            <span class="stat-label">Load Average</span>
                            <span class="stat-value">${data.system.load_average}</span>
                        </div>
                    </div>

                    <div class="card">
                        <h2>
                            <span class="icon">💾</span>
                            Memory Usage
                        </h2>
                        <div class="progress-label">
                            <span>${formatBytes(data.system.memory_used)}</span>
                            <span>${formatBytes(data.system.memory_total)}</span>
                        </div>
                        <div class="progress-bar">
                            <div class="progress-fill" style="width: ${data.system.memory_percent}%"></div>
                        </div>
                        <div class="stat">
                            <span class="stat-label">Used</span>
                            <span class="stat-value ${getStatusClass(data.system.memory_percent)}">${data.system.memory_percent.toFixed(1)}%</span>
                        </div>
                    </div>

                    <div class="card">
                        <h2>
                            <span class="icon">💿</span>
                            Disk Usage
                        </h2>
                        <div class="progress-label">
                            <span>${formatBytes(data.system.disk_used)}</span>
                            <span>${formatBytes(data.system.disk_total)}</span>
                        </div>
                        <div class="progress-bar">
                            <div class="progress-fill" style="width: ${data.system.disk_percent}%"></div>
                        </div>
                        <div class="stat">
                            <span class="stat-label">Used</span>
                            <span class="stat-value ${getStatusClass(data.system.disk_percent)}">${data.system.disk_percent.toFixed(1)}%</span>
                        </div>
                    </div>

                    <div class="card">
                        <h2>
                            <span class="icon">🔗</span>
                            Proxy Statistics
                        </h2>
                        <div class="stat">
                            <span class="stat-label">Total Plans</span>
                            <span class="stat-value">${data.proxies.total_plans}</span>
                        </div>
                        <div class="stat">
                            <span class="stat-label">Active Proxies</span>
                            <span class="stat-value success">${data.proxies.active_proxies}</span>
                        </div>
                        <div class="stat">
                            <span class="stat-label">Expired Proxies</span>
                            <span class="stat-value danger">${data.proxies.expired_proxies}</span>
                        </div>
                        <div class="stat">
                            <span class="stat-label">Server IP</span>
                            <span class="stat-value">${data.network.server_ip || 'Unknown'}</span>
                        </div>
                    </div>
                </div>

                <!-- Port Usage -->
                <div class="card">
                    <h2>
                        <span class="icon">📊</span>
                        Port Usage by Type (2000 ports per type)
                    </h2>
                    <div class="port-grid">
                        ${Object.entries(data.proxies.port_usage).map(([type, usage]) => ` + "`" + `
                            <div class="port-item ${usage.percentage > 0 ? 'active' : ''}">
                                <div class="port-name">${type}</div>
                                <div class="port-percent ${getStatusClass(usage.percentage)}">
                                    ${usage.percentage.toFixed(1)}%
                                </div>
                                <div class="port-usage">${usage.used}/${usage.total}</div>
                            </div>
                        ` + "`" + `).join('')}
                    </div>
                </div>

                <!-- Network Status -->
                <div class="grid grid-2">
                    <div class="card">
                        <h2>
                            <span class="icon">🌐</span>
                            Domain Status
                        </h2>
                        <div class="domain-grid">
                            ${Object.entries(data.network.subdomain_status).map(([subdomain, status]) => ` + "`" + `
                                <div class="domain-item">
                                    <div class="domain-name">${status.subdomain}.${baseDomain}</div>
                                    <div class="status-badge ${status.resolves ? 'success' : 'danger'}">
                                        ${status.resolves ? 'Resolves' : 'No DNS'}
                                    </div>
                                    <div class="status-badge ${status.is_listening ? 'success' : 'danger'}">
                                        Port ${status.port} ${status.is_listening ? 'Open' : 'Closed'}
                                    </div>
                                </div>
                            ` + "`" + `).join('')}
                        </div>
                    </div>

                    <div class="card">
                        <h2>
                            <span class="icon">🔌</span>
                            Open Ports
                        </h2>
                        <div class="domain-grid">
                            ${data.network.open_ports.map(port => ` + "`" + `
                                <div class="domain-item">
                                    <div class="domain-name">Port ${port.port} (${port.service})</div>
                                    <div></div>
                                    <div class="status-badge ${port.status === 'open' ? 'success' : 'danger'}">
                                        ${port.status}
                                    </div>
                                </div>
                            ` + "`" + `).join('')}
                        </div>
                    </div>
                </div>

                <!-- Recent Proxies -->
                <div class="card">
                    <h2>
                        <span class="icon">📋</span>
                        Recent Proxies
                    </h2>
                    <div class="proxy-list">
                        ${data.proxies.recent_proxies && data.proxies.recent_proxies.length > 0 ? 
                            data.proxies.recent_proxies.reverse().map(proxy => ` + "`" + `
                                <div class="proxy-item">
                                    <div class="proxy-info">
                                        <div class="proxy-username">${proxy.username}</div>
                                        <div class="proxy-details">
                                            ${proxy.subdomain}.${baseDomain}:${proxy.public_port || reversePortMap[proxy.subdomain] || 'N/A'} • 
                                            Local: ${proxy.local_port} • 
                                            Created: ${formatTimestamp(proxy.created_at * 1000 || Date.now())}
                                        </div>
                                    </div>
                                    <div class="status-badge ${proxy.expires_at === 0 || proxy.expires_at > Date.now()/1000 ? 'success' : 'danger'}">
                                        ${proxy.expires_at === 0 ? 'No Expiry' : (proxy.expires_at > Date.now()/1000 ? 'Active' : 'Expired')}
                                    </div>
                                </div>
                            ` + "`" + `).join('') : 
                            '<p style="text-align: center; color: #8892b0;">No proxies created yet</p>'
                        }
                    </div>
                </div>

                <!-- Footer -->
                <div style="text-align: center; margin-top: 30px; color: #8892b0;">
                    Last updated: ${formatTimestamp(data.last_updated)}
                </div>
            ` + "`" + `;

            document.getElementById('content').innerHTML = html;
        }

        const reversePortMap = {
            'usa': 1337,
            'eu': 1338,
            'alpha': 9876,
            'beta': 8765,
            'mobile': 7654,
            'unlim': 6543,
            'datacenter': 1339,
            'gamma': 5432,
            'delta': 4321,
            'epsilon': 3210,
            'zeta': 2109,
            'eta': 1098
        };

        // Initial load
        fetchData();

        // Refresh every 5 seconds
        setInterval(fetchData, 5000);
    </script>
</body>
</html>
`))

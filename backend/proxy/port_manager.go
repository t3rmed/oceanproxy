package proxy

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"sync"
)

var (
	portMutex sync.Mutex
	usedPorts = make(map[string]map[int]bool) // subdomain -> port -> used
)

// Port ranges for each subdomain (2000 ports each)
var portRanges = map[string]struct{ start, end int }{
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

// InitializePortManager loads used ports from the proxy log
func InitializePortManager() error {
	portMutex.Lock()
	defer portMutex.Unlock()

	// Read proxy log to populate used ports
	data, err := os.ReadFile(LogPath)
	if err != nil {
		if os.IsNotExist(err) {
			return nil // No proxy log yet
		}
		return err
	}

	var entries []Entry
	if err := json.Unmarshal(data, &entries); err != nil {
		return err
	}

	// Populate used ports map
	for _, entry := range entries {
		if usedPorts[entry.Subdomain] == nil {
			usedPorts[entry.Subdomain] = make(map[int]bool)
		}
		usedPorts[entry.Subdomain][entry.LocalPort] = true
	}

	return nil
}

// GetNextAvailablePort finds the next available port in the subdomain's range
func GetNextAvailablePort(subdomain string) (int, error) {
	portMutex.Lock()
	defer portMutex.Unlock()

	// Initialize map if needed
	if usedPorts[subdomain] == nil {
		usedPorts[subdomain] = make(map[int]bool)
	}

	// Get port range
	portRange, exists := portRanges[subdomain]
	if !exists {
		return 0, fmt.Errorf("unknown subdomain: %s", subdomain)
	}

	// Find next available port
	for port := portRange.start; port <= portRange.end; port++ {
		if !usedPorts[subdomain][port] && !isPortInUse(port) {
			usedPorts[subdomain][port] = true
			return port, nil
		}
	}

	return 0, fmt.Errorf("no available ports in range %d-%d for subdomain %s (capacity: 2000 ports)",
		portRange.start, portRange.end, subdomain)
}

// isPortInUse checks if a port is already in use
func isPortInUse(port int) bool {
	cmd := exec.Command("lsof", "-i", fmt.Sprintf("tcp:%d", port))
	err := cmd.Run()
	return err == nil // If lsof succeeds, port is in use
}

// ReleasePort marks a port as available
func ReleasePort(subdomain string, port int) {
	portMutex.Lock()
	defer portMutex.Unlock()

	if usedPorts[subdomain] != nil {
		delete(usedPorts[subdomain], port)
	}
}

// GetPortUsage returns the current port usage for each subdomain
func GetPortUsage() map[string]struct{ used, total int } {
	portMutex.Lock()
	defer portMutex.Unlock()

	usage := make(map[string]struct{ used, total int })

	for subdomain, portRange := range portRanges {
		used := 0
		if usedPorts[subdomain] != nil {
			used = len(usedPorts[subdomain])
		}
		total := portRange.end - portRange.start + 1
		usage[subdomain] = struct{ used, total int }{used, total}
	}

	return usage
}

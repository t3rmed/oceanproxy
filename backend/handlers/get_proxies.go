package handlers

import (
	"encoding/json"
	"net/http"
	"os"

	"oceanproxy-api/proxy"
)

func GetProxiesHandler(w http.ResponseWriter, r *http.Request) {
	data, err := os.ReadFile(proxy.LogPath)
	if err != nil {
		http.Error(w, "Read error", http.StatusInternalServerError)
		return
	}

	// Parse the data to potentially modify it for display
	var entries []proxy.Entry
	if err := json.Unmarshal(data, &entries); err != nil {
		http.Error(w, "Parse error", http.StatusInternalServerError)
		return
	}

	// Create a response that shows both local and public ports for clarity
	type ProxyDisplay struct {
		proxy.Entry
		ClientEndpoint string `json:"client_endpoint"`
	}

	var displayEntries []ProxyDisplay
	for _, entry := range entries {
		displayEntries = append(displayEntries, ProxyDisplay{
			Entry:          entry,
			ClientEndpoint: entry.LocalHost + ":" + string(rune(entry.PublicPort)),
		})
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(displayEntries)
}

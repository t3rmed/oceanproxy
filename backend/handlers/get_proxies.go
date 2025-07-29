package handlers

import (
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
	w.Header().Set("Content-Type", "application/json")
	w.Write(data)
}

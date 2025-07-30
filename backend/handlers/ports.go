package handlers

import (
	"bytes"
	"encoding/json"
	"net/http"
	"os/exec"
	"strings"
)

func PortsInUseHandler(w http.ResponseWriter, r *http.Request) {
	cmd := exec.Command("lsof", "-iTCP", "-sTCP:LISTEN", "-Pn")

	var out bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &out

	err := cmd.Run()
	if err != nil {
		http.Error(w, "Failed to run lsof: "+err.Error()+"\n"+out.String(), http.StatusInternalServerError)
		return
	}

	lines := strings.Split(out.String(), "\n")
	var results []map[string]string

	// Skip the header (first line)
	for _, line := range lines[1:] {
		fields := strings.Fields(line)
		if len(fields) >= 9 {
			results = append(results, map[string]string{
				"command": fields[0],
				"pid":     fields[1],
				"user":    fields[2],
				"port":    fields[8],
			})
		}
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]interface{}{
		"ports_in_use": results,
	})
}

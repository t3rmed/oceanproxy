package proxy

import (
	"encoding/json"
	"os"
)

const LogPath = "/var/log/oceanproxy/proxies.json"

func LogProxy(e Entry) error {
	var entries []Entry
	if data, err := os.ReadFile(LogPath); err == nil {
		_ = json.Unmarshal(data, &entries)
	}
	entries = append(entries, e)
	return SaveProxyLog(entries)
}

func SaveProxyLog(entries []Entry) error {
	data, err := json.MarshalIndent(entries, "", "  ")
	if err != nil {
		return err
	}
	_ = os.MkdirAll("/var/log/oceanproxy", 0755)
	return os.WriteFile(LogPath, data, 0644)
}

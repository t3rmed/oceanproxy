#!/usr/bin/env python3
import json

# Read the proxy log
with open('/var/log/oceanproxy/proxies.json', 'r') as f:
    data = json.load(f)

# Fix the auth port for the failing plan
for entry in data:
    if entry['plan_id'] == '8cef29b7-b7b0-53f1-2364-52f1d45df58a':
        entry['auth_port'] = 13337
        print(f"✅ Fixed auth_port for plan {entry['plan_id'][:8]}... from 10808 to 13337")

# Save updated data
with open('/var/log/oceanproxy/proxies.json', 'w') as f:
    json.dump(data, f, indent=2)

print("🎉 Fixed auth_port in proxy log")

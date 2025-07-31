#!/usr/bin/env python3
import json

# Read the proxy log
with open('/var/log/oceanproxy/proxies.json', 'r') as f:
    data = json.load(f)

# Fix datacenter port to be in valid range (40000-49999)
for entry in data:
    if entry['subdomain'] == 'datacenter':
        entry['local_port'] = 40000
        print(f"✅ Updated datacenter plan {entry['plan_id'][:8]}... to port 40000")

# Save updated data
with open('/var/log/oceanproxy/proxies.json', 'w') as f:
    json.dump(data, f, indent=2)

print("🎉 Updated datacenter port to valid range")

#!/usr/bin/env python3
import json

# Port mapping
port_mapping = {
    "usa": 1337,
    "eu": 1338,
    "alpha": 9876,
    "beta": 8765,
    "mobile": 7654,
    "unlim": 6543,
    "datacenter": 1339
}

# Read the proxy log
with open('/var/log/oceanproxy/proxies.json', 'r') as f:
    data = json.load(f)

# Add missing public_port field
for entry in data:
    subdomain = entry['subdomain']
    entry['public_port'] = port_mapping.get(subdomain, 8080)
    print(f"✅ {entry['plan_id'][:8]}... ({entry['username']}) {subdomain} → public_port {entry['public_port']}")

# Save updated data
with open('/var/log/oceanproxy/proxies.json', 'w') as f:
    json.dump(data, f, indent=2)

print(f"\n🎉 Added public_port field to {len(data)} entries.")
